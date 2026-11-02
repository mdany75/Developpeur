"""Conversion de BioCLIP 2 en CoreML (les espèces, 1.6.3), lancée par scripts/preparer-bioclip.sh.

1. charge BioCLIP 2 par open_clip (dossier téléchargé, open_clip_config.json et
   open_clip_model.safetensors) ;
2. convertit l'encodeur d'images (entrée « image » 224 × 224 RVB, ramenée à [0, 1] par CoreML ; la
   normalisation de CLIP, moyenne et écart type par canal, faite dans le modèle) et l'encodeur de
   texte (entrée « text », 77 jetons int32) en ML Program fp16 ; sortie « embedding » (768 nombres,
   non normalisés : le connecteur les ramène à la norme 1) ;
3. compare les vecteurs CoreML à ceux de PyTorch (fp32) sur des images et des phrases : cosinus
   minimal attendu 0,99, sinon arrêt sans rien installer ;
4. vérifie que le tokeniseur de BioCLIP 2 rend les jetons du tokeniseur de CLIP (le même vocabulaire
   BPE que TokeniseurCLIP), et range quelques phrases et leurs jetons dans le contrat des essais ;
5. compile les deux paquets (.mlmodelc) dans le dossier des modèles, rangés d'un coup.

Toujours lancé avec python -I (aucun module du dossier courant). Aucune image ne part.
"""

import argparse
import json
import os
import shutil
import sys
import time

import numpy as np
import torch
import open_clip
import coremltools as ct
from PIL import Image, ImageDraw

GABARIT = "a photo of {}."
PHRASES_CONTRAT = [
    "a photo of Cardinalis cardinalis.",
    "a photo of Haliaeetus leucocephalus.",
    "a photo of Danaus plexippus.",
    "a photo of Acer saccharum.",
    "a photo of Amanita muscaria.",
    "a photo of Panthera leo.",
    "a photo of Rudbeckia hirta.",
    "a photo of a bird.",
    "a photo of Æsculus × carnea.",
]


class Attention(torch.nn.Module):
    """nn.MultiheadAttention réécrite en opérations simples, avec les mêmes poids : coremltools ne
    convertit ni son chemin rapide (_native_multi_head_attention) ni son chemin lent (op « int »
    refusée, constaté le 2 nov. 2026 avec torch 2.7.0 et coremltools 9.0)."""

    def __init__(self, mha):
        super().__init__()
        self.tetes = mha.num_heads
        self.largeur_tete = mha.embed_dim // mha.num_heads
        self.echelle = float(self.largeur_tete) ** -0.5
        self.batch_first = mha.batch_first
        self.in_proj_weight = mha.in_proj_weight
        self.in_proj_bias = mha.in_proj_bias
        self.out_proj = mha.out_proj

    def forward(self, q, k, v, need_weights=False, attn_mask=None):
        if not self.batch_first:
            q = q.transpose(0, 1)
        # Aucune taille lue sur le tenseur (elle se tracerait en op « int ») : des constantes.
        qkv = torch.nn.functional.linear(q, self.in_proj_weight, self.in_proj_bias)
        qkv = qkv.unflatten(-1, (3, self.tetes, self.largeur_tete)).permute(2, 0, 3, 1, 4)
        a = (qkv[0] * self.echelle) @ qkv[1].transpose(-2, -1)
        if attn_mask is not None:
            a = a + attn_mask
        x = (a.softmax(dim=-1) @ qkv[2]).permute(0, 2, 1, 3).flatten(2)
        x = self.out_proj(x)
        if not self.batch_first:
            x = x.transpose(0, 1)
        return x, None


def charger(dossier):
    model, _, preprocess = open_clip.create_model_and_transforms("local-dir:" + dossier)
    tokenizer = open_clip.get_tokenizer("local-dir:" + dossier)
    model.eval()
    return model, preprocess, tokenizer


def remplacer_attention(model):
    """Chaque nn.MultiheadAttention (autoattention) remplacée par Attention, pour la conversion."""
    for module in list(model.modules()):
        for nom, enfant in list(module.named_children()):
            if isinstance(enfant, torch.nn.MultiheadAttention):
                setattr(module, nom, Attention(enfant))


class EncodeurImage(torch.nn.Module):
    def __init__(self, model, moyenne, ecart):
        super().__init__()
        self.visual = model.visual
        self.register_buffer("moyenne", torch.tensor(moyenne, dtype=torch.float32).view(1, 3, 1, 1))
        self.register_buffer("ecart", torch.tensor(ecart, dtype=torch.float32).view(1, 3, 1, 1))

    def forward(self, image):
        return self.visual((image - self.moyenne) / self.ecart)


class EncodeurTexte(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, text):
        return self.model.encode_text(text.to(torch.long))


def images_essai(dossier, nombre=8):
    """Des JPEG ou PNG du dossier (les captures de docs/ par défaut) et deux images synthétiques."""
    images = []
    if dossier and os.path.isdir(dossier):
        for nom in sorted(os.listdir(dossier)):
            if nom.lower().endswith((".jpg", ".jpeg", ".png")) and len(images) < nombre:
                images.append((nom, Image.open(os.path.join(dossier, nom)).convert("RGB")))
    for i, couleur in enumerate([(200, 40, 30), (40, 120, 60)]):
        im = Image.new("RGB", (400, 300), (230, 230, 220))
        d = ImageDraw.Draw(im)
        d.ellipse((80 + 20 * i, 60, 300, 250), fill=couleur)
        d.rectangle((10, 200, 120, 290), fill=(30, 30, 90))
        images.append((f"synthetique-{i + 1}", im))
    return images


def cosinus(a, b):
    a = np.asarray(a, dtype=np.float64).ravel()
    b = np.asarray(b, dtype=np.float64).ravel()
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))


def taille(chemin):
    total = 0
    for racine, _, fichiers in os.walk(chemin):
        for f in fichiers:
            total += os.path.getsize(os.path.join(racine, f))
    return total


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--modele", required=True)
    p.add_argument("--sortie", required=True)
    p.add_argument("--modeles", required=True)
    p.add_argument("--images")
    p.add_argument("--especes")
    p.add_argument("--contrat")
    p.add_argument("--compte-rendu", required=True)
    a = p.parse_args()
    os.makedirs(a.sortie, exist_ok=True)
    rendu = {"modele": "imageomics/bioclip-2", "gabarit": GABARIT}

    debut = time.time()
    model, preprocess, tokenizer = charger(a.modele)
    config = json.load(open(os.path.join(a.modele, "open_clip_config.json")))
    pre = config["preprocess_cfg"]
    taille_image = config["model_cfg"]["vision_cfg"]["image_size"]
    rendu["pretraitement"] = {"moyenne": pre["mean"], "ecart": pre["std"], "taille": taille_image,
                              "interpolation": pre.get("interpolation"), "redimension": pre.get("resize_mode")}
    rendu["dimension"] = config["model_cfg"]["embed_dim"]
    # L'échelle du softmax du classement (Especes.echelleLogits dans le connecteur : 100).
    rendu["echelle_logits"] = round(float(model.logit_scale.exp()), 3)
    rendu["chargement_s"] = round(time.time() - debut, 1)
    print(f"  modèle chargé en {rendu['chargement_s']} s ; prétraitement {rendu['pretraitement']}", flush=True)

    # Le tokeniseur : celui de CLIP (même vocabulaire BPE), contexte 77.
    jetons_open = tokenizer(PHRASES_CONTRAT)
    jetons_clip = open_clip.tokenizer.tokenize(PHRASES_CONTRAT)
    meme = bool(torch.equal(jetons_open.long(), jetons_clip.long()))
    rendu["tokeniseur_identique_a_clip"] = meme
    print(f"  tokeniseur de BioCLIP 2 = tokeniseur de CLIP : {meme} ({type(tokenizer).__name__})", flush=True)
    if a.contrat:
        contrat = {"source": "open_clip.get_tokenizer('imageomics/bioclip-2'), contexte 77",
                   "phrases": [{"texte": t, "jetons": [int(x) for x in j if int(x) != 0]}
                               for t, j in zip(PHRASES_CONTRAT, jetons_open)]}
        with open(a.contrat, "w", encoding="utf-8") as f:
            json.dump(contrat, f, ensure_ascii=False, indent=1)
            f.write("\n")

    # Les vecteurs de référence (PyTorch, attention d'origine) se calculent avec `reference`, une
    # copie du modèle intacte ; la conversion part du modèle à l'attention réécrite.
    import copy
    reference = copy.deepcopy(model)
    remplacer_attention(model)

    # 1. L'encodeur d'images.
    enc_image = EncodeurImage(model, pre["mean"], pre["std"]).eval()
    exemple = torch.rand(1, 3, taille_image, taille_image)
    debut = time.time()
    with torch.no_grad():
        trace = torch.jit.trace(enc_image, exemple)
    ml_image = ct.convert(
        trace,
        inputs=[ct.ImageType(name="image", shape=(1, 3, taille_image, taille_image), scale=1 / 255.0,
                             bias=[0, 0, 0], color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="embedding")],
        convert_to="mlprogram", compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
    )
    ml_image.short_description = "BioCLIP 2 (imageomics, licence MIT) : encodeur d'images, 224 x 224, vecteur de 768."
    paquet_image = os.path.join(a.sortie, "bioclip2_image.mlpackage")
    shutil.rmtree(paquet_image, ignore_errors=True)
    ml_image.save(paquet_image)
    rendu["conversion_image_s"] = round(time.time() - debut, 1)
    print(f"  encodeur d'images converti en {rendu['conversion_image_s']} s", flush=True)

    # 2. L'encodeur de texte.
    enc_texte = EncodeurTexte(model).eval()
    exemple_t = tokenizer(["a photo of Cardinalis cardinalis."]).to(torch.int32)
    debut = time.time()
    with torch.no_grad():
        trace_t = torch.jit.trace(enc_texte, exemple_t)
    ml_texte = ct.convert(
        trace_t,
        inputs=[ct.TensorType(name="text", shape=(1, 77), dtype=np.int32)],
        outputs=[ct.TensorType(name="embedding")],
        convert_to="mlprogram", compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
    )
    ml_texte.short_description = "BioCLIP 2 (imageomics, licence MIT) : encodeur de texte, 77 jetons de CLIP, vecteur de 768."
    paquet_texte = os.path.join(a.sortie, "bioclip2_text.mlpackage")
    shutil.rmtree(paquet_texte, ignore_errors=True)
    ml_texte.save(paquet_texte)
    rendu["conversion_texte_s"] = round(time.time() - debut, 1)
    print(f"  encodeur de texte converti en {rendu['conversion_texte_s']} s", flush=True)

    # 3. La comparaison PyTorch (fp32) / CoreML (fp16).
    redim = [t for t in preprocess.transforms if type(t).__name__ in ("Resize", "CenterCrop", "ResizeKeepRatio")]
    images = images_essai(a.images)
    ecarts_image, temps_image = [], []
    vecteurs_image = []
    for nom, im in images:
        pil = im
        for t in redim:
            pil = t(pil)
        with torch.no_grad():
            ref = reference.encode_image(preprocess(im).unsqueeze(0))[0].numpy()
        debut = time.time()
        sortie = ml_image.predict({"image": pil})["embedding"]
        temps_image.append(time.time() - debut)
        c = cosinus(ref, sortie)
        ecarts_image.append({"image": nom, "cosinus": round(c, 5)})
        vecteurs_image.append((nom, np.asarray(sortie, dtype=np.float64).ravel()))
    phrases = ["a photo of Cardinalis cardinalis.", "a photo of Danaus plexippus.", "a photo of Acer saccharum.",
               "a photo of Ursus americanus.", "a photo of a red flower.", "a photo of a bird."]
    if a.especes and os.path.exists(a.especes):
        lignes = [l.rstrip("\n").split("\t") for l in open(a.especes, encoding="utf-8") if l.strip() and not l.startswith("#")]
        phrases += [GABARIT.format(l[2]) for l in lignes[1::max(1, len(lignes) // 20)][:20] if len(l) >= 3]
    ecarts_texte, temps_texte, vecteurs_texte = [], [], []
    for phrase in phrases:
        jetons = tokenizer([phrase]).to(torch.int32)
        with torch.no_grad():
            ref = reference.encode_text(jetons.long())[0].numpy()
        debut = time.time()
        sortie = ml_texte.predict({"text": jetons.numpy()})["embedding"]
        temps_texte.append(time.time() - debut)
        c = cosinus(ref, sortie)
        ecarts_texte.append({"phrase": phrase, "cosinus": round(c, 5)})
        vecteurs_texte.append((phrase, np.asarray(sortie, dtype=np.float64).ravel()))
    minimum = min([e["cosinus"] for e in ecarts_image] + [e["cosinus"] for e in ecarts_texte])
    rendu["comparaison"] = {"images": ecarts_image, "phrases": ecarts_texte, "cosinus_minimum": minimum,
                            "image_ms_moyen_python": round(1000 * float(np.mean(temps_image[1:] or temps_image)), 1),
                            "texte_ms_moyen_python": round(1000 * float(np.mean(temps_texte[1:] or temps_texte)), 1)}
    # Pour voir : la phrase la plus proche de chaque image, parmi les phrases d'essai.
    T = np.stack([v / np.linalg.norm(v) for _, v in vecteurs_texte])
    rendu["plus_proche"] = {nom: vecteurs_texte[int(np.argmax(T @ (v / np.linalg.norm(v))))][0] for nom, v in vecteurs_image}
    print(f"  cosinus minimal PyTorch/CoreML : {minimum:.5f}", flush=True)
    if minimum < 0.99:
        json.dump(rendu, open(a.compte_rendu, "w"), ensure_ascii=False, indent=1)
        sys.exit(f"Écart trop grand entre PyTorch et CoreML ({minimum:.4f} < 0,99) : rien n'est installé.")

    # 4. La compilation, rangée d'un coup dans le dossier des modèles.
    os.makedirs(a.modeles, exist_ok=True)
    rendu["installes"] = {}
    for paquet in (paquet_image, paquet_texte):
        debut = time.time()
        compile = ct.utils.compile_model(paquet)
        nom = os.path.basename(paquet).replace(".mlpackage", ".mlmodelc")
        cible = os.path.join(a.modeles, nom)
        provisoire = os.path.join(a.modeles, f".{nom}.{os.getpid()}")
        shutil.rmtree(provisoire, ignore_errors=True)
        shutil.move(compile, provisoire)
        shutil.rmtree(cible, ignore_errors=True)
        os.rename(provisoire, cible)
        rendu["installes"][nom] = {"octets": taille(cible), "compilation_s": round(time.time() - debut, 1),
                                   "paquet_octets": taille(paquet)}
        print(f"  {nom} : {taille(cible) / 1e6:.0f} Mo, compilé en {rendu['installes'][nom]['compilation_s']} s", flush=True)

    json.dump(rendu, open(a.compte_rendu, "w"), ensure_ascii=False, indent=1)
    print(json.dumps(rendu, ensure_ascii=False))


if __name__ == "__main__":
    main()
