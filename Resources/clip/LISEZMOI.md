# Vocabulaire du tokeniseur de CLIP

`bpe_simple_vocab_16e6.txt.gz` : le vocabulaire BPE de CLIP (openai/CLIP, licence MIT,
Copyright (c) 2021 OpenAI), le même que celui d'open_clip, que l'encodeur de texte de
MobileCLIP S2 attend (77 jetons). sha256 :
`924691ac288e54409236115652ad4aa250f48203de50a9e4722a6ecd48d6804a`.

Il sert à `TokeniseurCLIP` (Sources/DeveloppeurKit/TokeniseurCLIP.swift) : les essais
(`TokeniseurCLIPTests`) le lisent ici ; le connecteur installé le lit dans
`~/Library/Application Support/Developpeur/Modeles/` (où `./build.sh --install` le copie s'il manque).
