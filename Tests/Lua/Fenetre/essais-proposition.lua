-- essais-proposition.lua : la carte Proposition de la fenêtre Claude, hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua) : une proposition dépassée par une étape de Claude (correctif
-- 1.3.2, Conversation.clorePropositions : appliquée ou remplacée, la carte le dit, Accepter, Refuser
-- et Ajuster… grisés ; ni une autre photo, ni un classement, ni un aperçu, ni une erreur, ni une
-- décision de Dany ; match_series), venue d'essais-lecon.lua, retiré avec la leçon au correctif
-- 1.3.6 ; et une conversation d'avant ce correctif, qui porte encore des éléments `lecon` (la leçon
-- de la photo) et `exercice` (« Je le fais »), relue sans erreur, montrée sans eux, réécrite telle
-- quelle. Ni Claude, ni quota ; les fichiers vont dans un dossier personnel temporaire.
-- Lancé par scripts/tester-module.sh dans Tests/Lua/Fenetre, avec PLUGIN_DIR.

local S = require 'Simulation'

local reussis, echecs = 0, 0
local function essai(nom, fn)
    local ok, erreur = xpcall(fn, debug.traceback)
    if ok then
        reussis = reussis + 1
        print('ok     ' .. nom)
    else
        echecs = echecs + 1
        print('ÉCHEC  ' .. nom .. '\n' .. tostring(erreur))
    end
end

local function egal(attendu, obtenu, quoi)
    if attendu ~= obtenu then
        error(string.format('%s : attendu %q, obtenu %q', quoi or 'valeur', tostring(attendu), tostring(obtenu)), 2)
    end
end

local function vrai(condition, quoi)
    if not condition then
        error(quoi or 'condition fausse', 2)
    end
end

local function contient(texte, morceau, quoi)
    if type(texte) ~= 'string' or not texte:find(morceau, 1, true) then
        error(string.format('%s : %q introuvable dans %q', quoi or 'texte', morceau, tostring(texte)), 2)
    end
end

local Chemins = require 'Chemins'
local Conversation = require 'Conversation'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Json = require 'Json'
local Notation = require 'Notation'
local Stockage = require 'Stockage'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'
local prefs = Chemins.prefs()
prefs.nouvelleParPhoto = false

-- Le faux Claude Code dès le départ (une demande partie par erreur ne lance jamais le vrai), et
-- une petite image JPEG (en base64) pour son résultat d'outil (cas par défaut).
local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
prefs.cheminClaude = dossierTests .. '/faux-claude.sh'
prefs.cheminConnecteur = '/bin/echo'
local imageB64 = S.home .. '/image.b64'
S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/' .. require('Dispositions').imageVide('claire')) .. ' --out ' .. S.q(S.home .. '/image.jpg') .. ' >/dev/null 2>&1')
S.executer('/usr/bin/base64 -i ' .. S.q(S.home .. '/image.jpg') .. ' -o ' .. S.q(imageB64))
local env = 'FAUX_IMAGE_B64=' .. S.q(imageB64) .. ' '
local executerOriginal = S.modules.LrTasks.execute
S.modules.LrTasks.execute = function(commande)
    if commande:find('relais.sh', 1, true) then
        commande = env .. commande
    end
    return executerOriginal(commande)
end

-- La largeur du texte du fil (Fenetre.largeurTexte : D.texteFil dans la fenêtre B, après la colonne
-- auteur).
local D = Dispositions.dimensions()
local LARGEUR = D.texteFil

local function photoActive(id, nom)
    local photo = S.photo(id, nom)
    S.photoActive, S.selection = photo, { photo }
    return photo
end

-- Ouvre la fenêtre Claude et appelle fn(p, args) pendant qu'elle est ouverte ; une erreur de fn
-- remonte une fois la fenêtre fermée.
local function ouvrirFenetre(fn)
    local erreur
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function() fn(Fenetre.p, args) end, debug.traceback)
        erreur = not ok and e or nil
    end
    Fenetre.afficher()
    S.pendantFenetre = nil
    if erreur then
        error(erreur, 0)
    end
end

-- Une proposition dépassée par Claude (1.3.2) -----------------------------------------------------

-- La réponse du connecteur à une proposition (preview_settings) : sa photo et ses changements.
local function reponseProposition(photo, fichier, changements)
    return Json.encode({ mode = 'proposer', photo = { id = photo, fichier = fichier }, etape = 'proposition', changements = changements })
end

-- La réponse du connecteur à une écriture (apply_settings…) : une étape par photo, avec son id.
local function reponseEcriture(nom, photo, fichier, changements, id)
    return Json.encode({ mode = 'appliquer', resultats = { { photo = { id = photo, fichier = fichier }, etape = 'Claude · ' .. nom,
        etape_id = id or 7001, changements = changements } } })
end

-- Un appel d'outil dans le fil, puis sa réponse (nil : en cours) ; rend l'indice de son élément.
local function appelOutil(c, id, nom, entree, reponse, erreur)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = id, nom = 'mcp__developpeur__' .. nom, entree = entree } } })
    local indice = #c.elements
    for i, e in ipairs(c.elements) do
        if e.genre == 'outil' and e.appel == id then
            indice = i
        end
    end
    if reponse ~= nil then
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = id, textes = { reponse }, images = {}, erreur = erreur == true } } })
    end
    return indice
end

-- La dernière proposition du fil.
local function derniereProposition(c)
    for i = #c.elements, 1, -1 do
        if c.elements[i].genre == 'proposition' then
            return c.elements[i]
        end
    end
    return nil
end

local EXPOSITION = { { cle = 'Exposure2012', libelle = 'Exposition', avant = 0, apres = 0.3 } }

essai("Proposition dépassée (constaté le 22 octobre 2026) : une proposition qui attend, puis les mêmes réglages appliqués par Claude ; la carte le dit, Accepter, Refuser et Ajuster… grisés, Obtenir de nouveau actif", function()
    photoActive(53636309, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    local c = Moteur.courante
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        egal('focus', p.onglet, "Focus à l'ouverture (correctif 1.3.6)")
        Fenetre.majPhoto()
        egal(true, p.peutObtenir, 'Obtenir : une photo seule, Claude libre, rien en attente')
        -- Une proposition (sans photo_id : la photo active), qui attend : l'onglet Proposition la
        -- montre (celle d'Obtenir comme les autres, depuis le correctif 1.3.6), Obtenir grisé.
        appelOutil(c, 'p1', 'preview_settings', { settings = { Exposure2012 = 0.3 }, reason = 'Plus lumineuse' },
            reponseProposition(53636309, 'DSCF4961.RAF', EXPOSITION))
        local prop = derniereProposition(c)
        egal(53636309, prop.photo, 'sa photo lue dans la réponse')
        Fenetre.rafraichir()
        egal('proposition', p.onglet, "une proposition qui arrive : l'onglet Proposition")
        egal(true, p.enAttente)
        egal(false, p.peutObtenir, 'une proposition attend : Obtenir grisé')
        -- « Applique ta proposition, puis termine par la leçon de la photo. »
        Conversation.ajouterDemande(c, 'Applique ta proposition, puis termine par la leçon de la photo.')
        appelOutil(c, 'a1', 'apply_settings', { settings = { Exposure2012 = 0.3 }, step_name = 'passe 1 : lumière et couleur',
            reason = 'Plus lumineuse' })
        egal('enAttente', prop.etat, "l'étape pas encore écrite : la proposition attend")
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'a1', images = {}, erreur = false,
            textes = { reponseEcriture('passe 1 : lumière et couleur', 53636309, 'DSCF4961.RAF', EXPOSITION) } } } })
        egal('appliquee', prop.etat, 'les mêmes réglages : appliquée par Claude')
        egal('passe 1 : lumière et couleur', prop.etapeClaude)
        egal(nil, Conversation.propositionEnAttente(c), "plus rien n'attend")
        egal(prop, Conversation.propositionClose(c))
        Fenetre.rafraichir()
        egal(false, p.enAttente, 'Accepter, Refuser et Ajuster… grisés')
        egal(true, p.peutObtenir, "plus rien n'attend : Obtenir de nouveau actif")
        local phrase = "Appliquée par Claude (étape « passe 1 : lumière et couleur ») : elle n'attend plus votre accord."
        egal(phrase, Fenetre.phraseClose(prop))
        local carte = p.propositionTexte:gsub('\n', ' ')
        contient(carte, phrase, 'la carte le dit')
        contient(carte, 'Exposition : 0 → 0,3', 'puis ce qui était proposé')
        egal(phrase, (Fenetre.texteProposition(prop):match('^[^\n]*')), 'en tête')
        -- Un clic sur Accepter (le calque ne vérifie pas enabled) ne réapplique rien.
        egal(false, Moteur.repondre(true), 'Accepter : rien à accepter')
        egal('appliquee', prop.etat)
        -- Le fil le dit aussi.
        local texte = ''
        for _, l in ipairs(Fil.lignes(c, LARGEUR)) do
            if c.elements[l.element] == prop then
                texte = texte .. l.texte .. '\n'
            end
        end
        contient(texte, 'Proposition appliquée par Claude', 'la ligne du fil')
    end)
end)

essai("Proposition dépassée : d'autres réglages la disent remplacée ; une autre photo, un classement, un aperçu, une erreur ou une décision de Dany la laissent", function()
    local c = Conversation.nouvelle(1000)
    -- D'autres réglages sur sa photo (photo_id dans l'entrée) : remplacée.
    appelOutil(c, 'p1', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4961, 'DSCF4961.RAF', EXPOSITION))
    local p1 = derniereProposition(c)
    egal(4961, p1.photo)
    -- Une étape sur une autre photo : rien.
    appelOutil(c, 'a0', 'apply_settings', { photo_id = 4962, settings = { Exposure2012 = 0.3 }, step_name = 'autre' },
        reponseEcriture('autre', 4962, 'DSCF4962.RAF', EXPOSITION, 7000))
    egal('enAttente', p1.etat, 'une autre photo')
    -- Un classement sur sa photo (ne change pas l'image) : rien.
    appelOutil(c, 'm1', 'set_metadata', { photo_ids = { 4961 }, add_keywords = { 'Lac' }, step_name = 'mots-clés' },
        reponseEcriture('mots-clés', 4961, 'DSCF4961.RAF', { { cle = 'motsCles', avant = '', apres = 'Lac' } }, 7002))
    egal('enAttente', p1.etat, 'un classement')
    -- Un masque en proposition seulement (preview) : rien d'écrit.
    appelOutil(c, 'k1', 'add_mask', { photo_ids = { 4961 }, preview = true, masks = {} },
        reponseProposition(4961, 'DSCF4961.RAF', {}))
    egal('enAttente', p1.etat, 'un aperçu')
    -- Une écriture refusée : rien.
    appelOutil(c, 'a1', 'apply_settings', { photo_id = 4961, settings = { Exposure2012 = 0.5 } }, 'Proposer d\'abord : confirm = true.', true)
    egal('enAttente', p1.etat, 'une erreur')
    -- D'autres réglages : remplacée par une retouche de Claude.
    appelOutil(c, 'a2', 'apply_settings', { photo_id = 4961, settings = { Exposure2012 = 0.5 }, step_name = 'passe 1 : lumière' },
        reponseEcriture('passe 1 : lumière', 4961, 'DSCF4961.RAF', { { cle = 'Exposure2012', avant = 0, apres = 0.5 } }, 7003))
    egal('remplacee', p1.etat)
    egal('passe 1 : lumière', p1.etapeClaude)
    egal("Remplacée par une retouche de Claude (étape « passe 1 : lumière ») : elle n'attend plus votre accord.", Fenetre.phraseClose(p1))
    -- Une partie seulement des réglages proposés : remplacée aussi.
    appelOutil(c, 'p2', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3, Vibrance = 10 } },
        reponseProposition(4961, 'DSCF4961.RAF', { EXPOSITION[1], { cle = 'Vibrance', avant = 0, apres = 10 } }))
    local p2 = derniereProposition(c)
    appelOutil(c, 'a3', 'apply_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 }, step_name = 'lumière' },
        reponseEcriture('lumière', 4961, 'DSCF4961.RAF', EXPOSITION, 7004))
    egal('remplacee', p2.etat, 'la vibrance manque')
    -- Une proposition décidée par Dany garde son état ; la suivante, sans réglage lu, est remplacée.
    appelOutil(c, 'p3', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4961, 'DSCF4961.RAF', EXPOSITION))
    local p3 = derniereProposition(c)
    Conversation.decider(c, p3.id, true)
    appelOutil(c, 'p4', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 } }, '{ "texte": "sans réglages lus" }')
    local p4 = derniereProposition(c)
    appelOutil(c, 'a4', 'copy_settings', { from_photo_id = 4961, photo_ids = { 4961 }, step_name = 'copie' },
        reponseEcriture('copie', 4961, 'DSCF4961.RAF', EXPOSITION, 7005))
    egal('acceptee', p3.etat, 'acceptée par Dany : son chemin')
    egal('remplacee', p4.etat, 'aucun réglage lu : rien ne dit les mêmes')
    -- La carte : la dernière proposition, si Claude l'a close ; nil après une décision de Dany.
    egal(p4, Conversation.propositionClose(c))
    appelOutil(c, 'p5', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4961, 'DSCF4961.RAF', EXPOSITION))
    Conversation.decider(c, derniereProposition(c).id, false)
    egal(nil, Conversation.propositionClose(c), 'refusée par Dany')
    egal(nil, Fenetre.phraseClose(derniereProposition(c)))
    -- Relue du disque, une proposition close le reste.
    local relue = Json.decode(Json.encode(p1))
    egal('remplacee', relue.etat)
    egal(Fenetre.phraseClose(p1), Fenetre.phraseClose(relue))
end)

essai("Proposition dépassée : une proposition sans photo connue (d'avant le correctif) attend encore après une étape, sur quelque photo que ce soit", function()
    local c = Conversation.nouvelle(1000)
    -- Une proposition enregistrée avant le correctif 1.3.2 : sans champ photo.
    appelOutil(c, 'p0', 'preview_settings', { settings = { Exposure2012 = 0.3 } }, reponseProposition(4961, 'DSCF4961.RAF', EXPOSITION))
    local ancienne = derniereProposition(c)
    ancienne.photo = nil
    ancienne = Json.decode(Json.encode(ancienne))
    c.elements[#c.elements] = ancienne
    egal(nil, ancienne.photo)
    -- Claude retouche une autre photo : la proposition (sur la photo active d'alors) attend encore.
    appelOutil(c, 'a0', 'apply_settings', { photo_id = 4962, settings = { Exposure2012 = 0.5 }, step_name = 'autre photo' },
        reponseEcriture('autre photo', 4962, 'DSCF4962.RAF', { { cle = 'Exposure2012', avant = 0, apres = 0.5 } }, 7100))
    egal('enAttente', ancienne.etat, 'une étape sur une autre photo ne la clôt pas')
    egal(nil, ancienne.etapeClaude)
    egal(ancienne, Conversation.propositionEnAttente(c), 'Accepter reste offert')
    -- Même les mêmes réglages sur une photo : sa photo n'est pas connue, elle attend.
    appelOutil(c, 'a1', 'apply_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 }, step_name = 'mêmes réglages' },
        reponseEcriture('mêmes réglages', 4961, 'DSCF4961.RAF', EXPOSITION, 7101))
    egal('enAttente', ancienne.etat, 'photo inconnue : comme avant le correctif')
    -- Une réponse qui ne dit pas la photo de la proposition (sans photo_id dans l'entrée) : de même.
    appelOutil(c, 'p1', 'preview_settings', { settings = { Exposure2012 = 0.3 } }, '{ "texte": "sans photo dite" }')
    local sansPhoto = derniereProposition(c)
    egal(nil, sansPhoto.photo)
    appelOutil(c, 'a2', 'apply_settings', { photo_id = 4963, settings = { Exposure2012 = 0.3 }, step_name = 'troisième' },
        reponseEcriture('troisième', 4963, 'DSCF4963.RAF', EXPOSITION, 7102))
    egal('enAttente', sansPhoto.etat)
end)

essai("Proposition dépassée : match_series clôt la proposition d'une photo qu'il harmonise ; ni celle de la référence, ni un plan", function()
    local c = Conversation.nouvelle(1000)
    local REFERENCE = { id = 4961, fichier = 'DSCF4961.RAF' }
    appelOutil(c, 'p1', 'preview_settings', { photo_id = 4962, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4962, 'DSCF4962.RAF', EXPOSITION))
    local surSerie = derniereProposition(c)
    appelOutil(c, 'p2', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4961, 'DSCF4961.RAF', EXPOSITION))
    local surReference = derniereProposition(c)
    -- Un plan (sans confirm) : rien d'écrit, toutes attendent.
    appelOutil(c, 's0', 'match_series', { reference_id = 4961, photo_ids = { 4962 } }, Json.encode({ reference = REFERENCE,
        photos = { { id = 4962, fichier = 'DSCF4962.RAF', correction_proposee = { Exposure2012 = 0.2 } } }, rien_n_est_applique = 'Plan seulement.' }))
    egal('enAttente', surSerie.etat, 'un plan')
    egal('enAttente', surReference.etat)
    -- Une photo déjà proche de la référence : rien d'écrit.
    appelOutil(c, 's1', 'match_series', { reference_id = 4961, photo_ids = { 4962 }, confirm = true }, Json.encode({ reference = REFERENCE,
        photos = { { id = 4962, fichier = 'DSCF4962.RAF', correction = 'aucune : déjà proche de la référence' } } }))
    egal('enAttente', surSerie.etat, 'rien à corriger')
    -- Harmonisée par la mesure (deux passes, sans etape_id) : la proposition de la photo est
    -- remplacée ; celle de la référence, que match_series ne touche pas, attend.
    appelOutil(c, 's2', 'match_series', { reference_id = 4961, photo_ids = { 4962 }, confirm = true, step_name = 'harmonisation' },
        Json.encode({ reference = REFERENCE, photos = { { id = 4962, fichier = 'DSCF4962.RAF',
            correction_proposee = { Exposure2012 = 0.2 }, etapes = { 'Claude · harmonisation : passe 1', 'Claude · harmonisation : passe 2' } } } }))
    egal('remplacee', surSerie.etat, "harmonisée : Accepter poserait l'ancienne proposition par-dessus")
    egal('harmonisation : passe 1', surSerie.etapeClaude)
    egal('enAttente', surReference.etat, 'la référence ne change pas')
    egal(surReference, Conversation.propositionEnAttente(c))
    -- Par la prise de vue (by = exif) : `etape`.
    appelOutil(c, 'p3', 'preview_settings', { photo_id = 4963, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4963, 'DSCF4963.RAF', EXPOSITION))
    local exif = derniereProposition(c)
    appelOutil(c, 's3', 'match_series', { reference_id = 4961, photo_ids = { 4963 }, by = 'exif', confirm = true },
        Json.encode({ reference = REFERENCE, photos = { { id = 4963, fichier = 'DSCF4963.RAF', etape = 'Claude · expositions reproduites' } } }))
    egal('remplacee', exif.etat)
    egal('expositions reproduites', exif.etapeClaude)
    egal("Remplacée par une retouche de Claude (étape « expositions reproduites ») : elle n'attend plus votre accord.", Fenetre.phraseClose(exif))
    -- Une réponse en erreur : rien.
    appelOutil(c, 's4', 'match_series', { reference_id = 4962, photo_ids = { 4961 }, confirm = true }, 'Aucune photo à harmoniser.', true)
    egal('enAttente', surReference.etat, 'une erreur')
end)


-- Une conversation d'avant le correctif 1.3.6 (leçon et « Je le fais » retirés) -------------------

-- Une conversation telle que la 1.3.5 l'écrivait : une leçon faite (son appel de photo_lesson, puis
-- l'élément `lecon`, points et défauts en tableaux, un vide), un exercice « Je le fais » comparé (son
-- appel de preview_settings avec my_turn, l'élément `exercice` et sa liste), la proposition qu'il a
-- rendue « à faire vous-même » et un autre exercice resté en cours.
local ANCIENNE = [[{"format":"developpeur/1","id":"ancienne-135","titre":"Héron au bord du lac","titreAuto":true,
"creee":1000,"modifiee":2000,"cle":"53636309:1:53636309","elements":[
{"id":"e1","genre":"dany","texte":"Retouche cette photo, puis la leçon.","date":1000,"images":[],"changements":[]},
{"id":"e2","genre":"outil","outil":"photo_lesson","appel":"l1","etat":"fait","texte":"photo_lesson","date":1001,"images":[],"changements":[],
"detail":"{\"photo_id\":53636309}\n\n— Réponse —\n{\"lecon\":{\"rangee\":true}}"},
{"id":"e3","genre":"lecon","outil":"photo_lesson","appel":"l1","etat":"fait","photo":53636309,"fichier":"DSCF4961.RAF","rangee":true,
"date":1001,"images":[],"changements":[],"points":[{"axe":"light","nom":"Lumière","manque":"Ciel brûlé.","prise_de_vue":"Compenser.",
"defauts":["blown_highlights"]},{"axe":"color","nom":"Couleur","prise_de_vue":"Rien.","defauts":[]}]},
{"id":"e4","genre":"proposition","outil":"preview_settings","appel":"p1","etat":"faite","texte":"Plus lumineuse","date":1002,
"images":[],"changements":[{"cle":"Exposure2012","libelle":"Exposition","avant":"0","apres":"0,3"}],"photo":53636309},
{"id":"e5","genre":"outil","outil":"preview_settings","appel":"j1","etat":"fait","texte":"preview_settings","date":1003,"images":[],
"changements":[],"detail":"{\"my_turn\":true}"},
{"id":"e6","genre":"exercice","outil":"preview_settings","appel":"j1","etat":"comparee","photo":53636309,"date":1003,"images":[],
"changements":[],"aFaire":[{"n":1,"cle":"Exposure2012","cles":["Exposure2012"],"texte":"Exposition : 0 → +0,3"}],"ecarts":[],
"commeClaude":[],"instantane":"Claude · ma version"},
{"id":"e7","genre":"exercice","outil":"preview_settings","appel":"j2","etat":"enCours","photo":53636309,"date":1004,"images":[],
"changements":[],"aFaire":[],"ecarts":[]},
{"id":"e8","genre":"claude","texte":"Voilà la retouche.","date":1005,"images":[],"changements":[]}]}]]

essai("Conversation d'avant le correctif 1.3.6 : ses éléments lecon et exercice se relisent sans erreur, ne se montrent plus, et se réécrivent tels quels", function()
    Fichiers.ecrire(Stockage.fichier('ancienne-135'), ANCIENNE)
    local c = Stockage.lire('ancienne-135')
    vrai(c, 'relue')
    egal(8, #c.elements, 'tous ses éléments, lecon et exercice compris')
    egal('lecon', c.elements[3].genre)
    egal('exercice', c.elements[6].genre)
    egal('enCours', c.elements[7].etat, "rien n'en est plus lu : un exercice resté en cours reste tel quel")
    -- Le fil : l'appel de chaque outil garde sa ligne ; la leçon et les exercices n'en ont aucune.
    local parElement = {}
    for _, l in ipairs(Fil.lignes(c, LARGEUR)) do
        if l.element then
            parElement[l.element] = (parElement[l.element] or 0) + 1
        end
        vrai(l.actions == nil or l.actions == 'note', 'ligne d\'actions : ' .. tostring(l.actions))
    end
    egal(1, parElement[2], "l'appel de photo_lesson, une ligne")
    egal(nil, parElement[3], 'la leçon : aucune ligne')
    egal(1, parElement[5], "l'appel de preview_settings, une ligne")
    egal(nil, parElement[6], "l'exercice : aucune ligne")
    egal(nil, parElement[7])
    vrai(parElement[4] and parElement[4] >= 1, 'la proposition « à faire vous-même » reste dans le fil')
    egal(nil, Conversation.propositionEnAttente(c), "rien n'attend")
    egal(nil, Conversation.propositionClose(c))
    -- Réécrite (une demande de plus, par exemple) : la leçon et l'exercice restent mot pour mot.
    Stockage.enregistrer(c)
    local relue = Json.decode(Fichiers.lire(Stockage.fichier('ancienne-135')))
    local avant = Json.decode(ANCIENNE)
    for _, k in ipairs({ 3, 6, 7 }) do
        -- (Stockage.lire pose partiel = false sur chaque élément, comme avant.)
        egal(false, relue.elements[k].partiel)
        relue.elements[k].partiel = nil
        egal(Json.encode(avant.elements[k]), Json.encode(relue.elements[k]), 'élément ' .. k .. ' réécrit tel quel')
    end
    vrai(Fichiers.lire(Stockage.fichier('ancienne-135')):find('"defauts":[]', 1, true), 'une liste vide reste un tableau')
    -- Montrée dans la fenêtre : rien ne casse, la carte Proposition n'a rien à décider.
    photoActive(53636309, 'DSCF4961.RAF')
    -- Relue du disque avec les autres (Moteur.charger ne charge qu'une fois).
    Moteur.charge = false
    Moteur.charger()
    egal(true, Moteur.ouvrir('ancienne-135'), 'ouverte comme une autre')
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        egal('focus', p.onglet, "Focus à l'ouverture (correctif 1.3.6)")
        egal(false, p.enAttente)
        contient(p.propositionTexte, "Aucune proposition en attente.", "l'aide de la carte")
        egal(nil, p.titreJeLeFais)
    end)
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
