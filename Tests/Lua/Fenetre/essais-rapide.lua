-- essais-rapide.lua : la fenêtre Demande rapide (FenetreRapide.lua) hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua) : ses boutons à icône à gauche du champ, sans ♻, et la
-- réponse effacée quand Dany choisit une autre photo ou une autre sélection (demandé par Dany le
-- 24 octobre 2026), mais pas quand la sélection change pendant le travail de Claude ou juste
-- après. Depuis le correctif 1.3.6 (« une photo, une conversation », Moteur.envoyerRapide) : une
-- photo seule, dans sa conversation existante (sans la montrer, la session de la photo reprise,
-- seule la réponse à la demande montrée), ou dans une conversation créée avec son historique et
-- gardée ; plusieurs photos, dans une conversation jamais gardée avec le résumé du groupe ; la
-- mention « Demande rapide » dans le fil de la fenêtre Claude, qui se met à jour ; un seul Claude
-- Code à la fois. Le catalogue est complété ici, comme dans essais-une-photo.lua, et Claude Code est
-- remplacé par une fausse session qui garde les messages reçus : ni Claude, ni quota.
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

-- Toutes les vues d'un arbre, avec la marge gauche de la pièce qui les porte.
local function vues(contenu)
    local liste = {}
    local function parcourir(v, marge)
        marge = (v.args and v.args.margin_left) or marge
        liste[#liste + 1] = { vue = v, marge = marge }
        for _, enfant in ipairs(v.args or {}) do
            if type(enfant) == 'table' and enfant.genre then
                parcourir(enfant, marge)
            end
        end
    end
    parcourir(contenu, 0)
    return liste
end

local function contient(texte, morceau, quoi)
    if not tostring(texte or ''):find(morceau, 1, true) then
        error(string.format('%s : %q ne contient pas %q', quoi or 'texte', tostring(texte), morceau), 2)
    end
end

local function absent(texte, morceau, quoi)
    if tostring(texte or ''):find(morceau, 1, true) then
        error(string.format('%s : %q contient %q', quoi or 'texte', tostring(texte), morceau), 2)
    end
end

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Historique = require 'Historique'
local Json = require 'Json'
local Lightroom = require 'Lightroom'
local Session = require 'Session'
local Stockage = require 'Stockage'

local prefs = Chemins.prefs()
prefs.nouvelleParPhoto = true

-- Le catalogue : des photos par identifiant (getPhotoByLocalId), avec editCount, lastEditTime et
-- leurs réglages (getDevelopSettings), et leurs champs du module posés directement.
local photos = {}
local function photo(id)
    local p = S.photo(id, string.format('DSCF%04d.RAF', id))
    p.editCount, p.lastEditTime, p.reglages = 0, 0, { Exposure2012 = 0 }
    local brut = p.getRawMetadata
    p.getRawMetadata = function(self, cle)
        if cle == 'editCount' then
            return self.editCount
        elseif cle == 'lastEditTime' then
            return self.lastEditTime
        end
        return brut(self, cle)
    end
    p.getDevelopSettings = function(self)
        local t = {}
        for k, v in pairs(self.reglages) do
            t[k] = v
        end
        return t
    end
    photos[id] = p
    return p
end
S.catalogue.getPhotoByLocalId = function(_, id) return photos[tonumber(id)] end

-- Le journal de Claude d'une photo (Ecriture.ajouterJournal) : des étapes datées.
local function journal(p, entrees)
    local liste = {}
    for k, e in ipairs(entrees) do
        liste[k] = { date = e[1], etape = 'Claude · ' .. e[2], etape_id = e[2], type = 'retouche', raison = e[3], changements = {} }
    end
    p.proprietes.journalClaude = Json.encode(Json.tableau(liste))
end

-- La sélection de Lightroom : la photo active, puis les autres.
local function choisir(active, ...)
    S.photoActive = photos[active]
    local liste = { photos[active] }
    for _, id in ipairs({ ... }) do
        liste[#liste + 1] = photos[id]
    end
    S.selection = liste
end

-- Une fausse session de Claude Code : les messages reçus, la session reprise (`reprise`) et la
-- conversation ; `arrete` quand elle est fermée.
local recus = {}
local sessions = 0
Session.nouvelle = function(options)
    sessions = sessions + 1
    local s = {}
    for k, v in pairs(options) do
        s[k] = v
    end
    function s.envoyer(_, message) recus[#recus + 1] = { message = message, reprise = options.reprise, conversation = options.idConversation } end
    -- Les lignes de Claude Code à lire (repondre), comme sortie.jsonl.
    function s.lire(this)
        local lignes = this.aLire or {}
        this.aLire = {}
        return lignes, false
    end
    function s.arreter(this) this.arrete = true end
    function s.interrompre() end
    return s
end

local Moteur = require 'Moteur'
local FenetreRapide = require 'FenetreRapide'
local Fenetre = require 'Fenetre'

-- Le moteur au départ d'un essai : `conversations` gardées (sur le disque aussi, seules), la
-- conversation montrée par la fenêtre Claude ; rien de la Demande rapide.
local function depart(conversations, courante)
    Fichiers.supprimer(Chemins.conversations())
    Moteur.charge = true
    Moteur.travaille, Moteur.finTravail, Moteur.enCours, Moteur.session = false, 0, nil, nil
    Moteur.rapide, Moteur.demandeRapide, Moteur.tourRapide, Moteur.selectionRapide = nil, nil, nil, nil
    Moteur.conversations = conversations or {}
    for _, c in ipairs(Moteur.conversations) do
        Stockage.enregistrer(c)
    end
    Moteur.courante = courante or Conversation.nouvelle()
    Fenetre.cleVue, Fenetre.cleVueLe = nil, nil
    FenetreRapide.cleVue, FenetreRapide.cleVueLe, FenetreRapide.message = nil, nil, nil
end

-- Une conversation gardée pour une photo : une demande, la réponse de Claude, sa session ; ce
-- qu'elle a vu de la photo (son état d'à présent).
local function gardee(id, titre)
    local c = Conversation.nouvelle(os.time() - 3600)
    c.photo = id
    Conversation.ajouterDemande(c, 'Retouche-la', os.time() - 3600)
    c.elements[#c.elements + 1] = { id = 'claude-' .. id, genre = 'claude', texte = 'Fait.', date = os.time() - 3600, images = {}, changements = {} }
    c.titre, c.titreAuto = titre, true
    c.sessionID = 'session-' .. id
    local etat = Historique.lire(id)
    c.vu = etat and Historique.vu(etat) or nil
    return c
end

-- Claude répond à la demande en cours, puis finit son tour : ses lignes stream-json lues par un tour
-- de la boucle du moteur (Moteur.tic), une minute avant la suite.
local function repondre(texte)
    local c = Moteur.enCours
    vrai(c and Moteur.session, 'une demande en cours')
    Moteur.session.aLire = {
        Json.encode({ type = 'assistant', message = { content = Json.tableau({ { type = 'text', text = texte } }) } }),
        Json.encode({ type = 'result', subtype = 'success', session_id = 'session-' .. c.id }),
    }
    Moteur.tic()
    vrai(not Moteur.travaille, 'tour fini')
    Moteur.finTravail = os.time() - 60
end

-- Les éléments d'une conversation de ce genre.
local function elements(c, genre)
    local liste = {}
    for _, e in ipairs(c.elements) do
        if e.genre == genre then
            liste[#liste + 1] = e
        end
    end
    return liste
end

essai("Les boutons à icône à gauche du champ, sans ♻ ; le titre de la fenêtre, sans version", function()
    local contenu, titre
    S.pendantFenetre = function(args) contenu, titre = args.contents, args.title end
    FenetreRapide.afficher()
    S.pendantFenetre = nil
    vrai(contenu, 'fenêtre ouverte')
    -- La Demande rapide garde son titre (seule la fenêtre Claude dit sa version, correctif 1.3.6).
    egal('Claude · Demande rapide', titre)
    local icones, champ = {}, nil
    for _, v in ipairs(vues(contenu)) do
        local a = v.vue.args or {}
        vrai(a.title ~= "♻", 'plus de bouton ♻')
        if v.vue.genre == 'square_button' and a.image_name then
            icones[#icones + 1] = v.marge or 0
            egal(FenetreRapide.CARRE, a.width, 'carré')
        elseif v.vue.genre == 'edit_field' then
            champ = v.marge
        end
    end
    egal(#FenetreRapide.ACTIONS, #icones, 'un carré par action')
    local pas = FenetreRapide.CARRE + FenetreRapide.ESPACE
    for i, marge in ipairs(icones) do
        egal((i - 1) * pas, marge, 'marge du carré ' .. i)
    end
    egal(#FenetreRapide.ACTIONS * pas - FenetreRapide.ESPACE + FenetreRapide.ECART, champ, 'le champ après les carrés')
    vrai(FenetreRapide.reinitialiser == nil, 'plus de reinitialiser')
end)

essai("Le texte de la fenêtre vide (case Autre photo cochée comprise) tient en entier dans la zone du résultat, sans ▼", function()
    depart({})
    contient(FenetreRapide.VIDE, 'Pour une photo seule (case Autre photo cochée), elle part dans sa conversation')
    local p
    S.pendantFenetre = function() p = FenetreRapide.p end
    FenetreRapide.afficher()
    S.pendantFenetre = nil
    vrai(p, 'fenêtre ouverte')
    local page = FenetreRapide.page
    egal(FenetreRapide.VIDE, page.texte, 'le texte vide montré')
    vrai(#page.lignes <= FenetreRapide.LIGNES_RESULTAT, string.format('%d lignes pour %d', #page.lignes, FenetreRapide.LIGNES_RESULTAT))
    egal(false, p.descend, 'sans ▼ : tout se voit')
    egal(false, p.monte)
    egal(table.concat(page.lignes, '\n'), p.resultat, 'toutes ses lignes montrées')
    for _, l in ipairs(page.lignes) do
        vrai(Fil.largeur(l, 'texte') <= FenetreRapide.LARGEUR_TEXTE - Fil.MARGE, 'dans la largeur : ' .. l)
    end
    egal(FenetreRapide.VIDE, (table.concat(page.lignes, ' '):gsub('  +', ' ')), 'en entier')
end)

-- Une demande rapide finie (sur plusieurs photos : jetable), montrée dans la fenêtre.
local function reponse()
    Moteur.rapide, Moteur.demandeRapide = { id = 'r', rapide = true, elements = {} }, nil
    Moteur.travaille, Moteur.enCours, Moteur.session = false, nil, nil
end

essai("Une autre photo ou une autre sélection efface la réponse ; le champ reste", function()
    FenetreRapide.cleVue, FenetreRapide.cleVueLe, FenetreRapide.message = nil, nil, nil
    Moteur.finTravail = os.time() - 60
    reponse()
    FenetreRapide.suivreSelection({ cle = '1:1:1' })
    vrai(Moteur.rapide, 'première sélection vue : rien ne change')
    FenetreRapide.suivreSelection({ cle = '1:1:1' })
    vrai(Moteur.rapide, 'même sélection : la réponse reste')
    FenetreRapide.p = { demande = 'Rends le ciel plus doux' }
    FenetreRapide.suivreSelection({ cle = '2:1:2' })
    egal(nil, Moteur.rapide, 'autre photo : demande oubliée')
    egal('Rends le ciel plus doux', FenetreRapide.p.demande, 'ce qui est tapé reste')
    FenetreRapide.p = nil
    egal(FenetreRapide.VIDE, FenetreRapide.texte(0), 'la réponse effacée')
    -- Un message seul (un refus, une erreur) s'efface de même.
    FenetreRapide.message = "Claude travaille déjà"
    FenetreRapide.suivreSelection({ cle = '2:3:2:4:5' })
    egal(nil, FenetreRapide.message, 'autre sélection : message effacé')
    -- Sans photo active (rien de sélectionné), rien ne change.
    reponse()
    FenetreRapide.suivreSelection({})
    vrai(Moteur.rapide, 'sans clé : la réponse reste')
    egal('2:3:2:4:5', FenetreRapide.cleVue)
end)

essai("La sélection changée par Claude, pendant son travail ou juste après, garde la réponse", function()
    FenetreRapide.cleVue, FenetreRapide.cleVueLe, FenetreRapide.message = '1:1:1', os.time(), nil
    reponse()
    Moteur.travaille = true
    FenetreRapide.suivreSelection({ cle = '9:1:9' })
    vrai(Moteur.rapide, 'pendant le travail (show_photo) : la réponse reste')
    Moteur.travaille, Moteur.finTravail = false, os.time()
    FenetreRapide.suivreSelection({ cle = '9:2:9:8' })
    vrai(Moteur.rapide, 'juste après le travail : la réponse reste')
    -- Plus tard, c'est Dany qui choisit.
    FenetreRapide.cleVueLe = os.time() - 10
    Moteur.finTravail = os.time() - 20
    FenetreRapide.suivreSelection({ cle = '3:1:3' })
    egal(nil, Moteur.rapide, 'choisie par Dany : demande oubliée')
end)

-- Une photo, une conversation (correctif 1.3.6) ------------------------------------------------

essai("Photo seule : la demande rapide part dans sa conversation, sans la montrer ; Claude reprend sa session ; seule la réponse à la demande se montre", function()
    photo(501)
    photo(502)
    local c501 = gardee(501, 'Lac au matin')
    local c502 = gardee(502, 'Cinq cent deux')
    c502.modifiee = os.time() - 60
    depart({})
    -- La fenêtre Claude ne s'est pas encore ouverte : les conversations ne sont que sur le disque.
    -- Chargées, la plus récente (celle de la 502) est la conversation montrée ; celle de la photo
    -- choisie se retrouve.
    Stockage.enregistrer(c501)
    Stockage.enregistrer(c502)
    Moteur.charge = false
    choisir(501)
    FenetreRapide.p = { demande = 'Rends le ciel plus doux' }
    local taches = #S.taches
    FenetreRapide.envoyer()
    vrai(#S.taches > taches, 'la demande part dans une tâche')
    S.taches[#S.taches]()
    egal('', FenetreRapide.p.demande, 'le champ vidé')
    local c = Moteur.rapide
    vrai(c, 'la demande rapide')
    egal(c501.id, c.id, 'dans la conversation de la photo')
    egal(c, Moteur.conversationDe(501), 'la même que la fenêtre Claude')
    vrai(not c.rapide, 'pas une conversation jetable')
    egal(c502.id, Moteur.courante.id, 'sans la montrer dans la fenêtre Claude')
    egal('session-501', recus[#recus].reprise, 'Claude reprend la session de la photo')
    egal(c.id, recus[#recus].conversation)
    local message = recus[#recus].message
    contient(message, Consignes.rapidePhoto, 'les règles courtes de la Demande rapide')
    contient(message, 'Rends le ciel plus doux')
    absent(message, Consignes.rappelTitre, 'ni titre')
    local demandes = elements(c, 'dany')
    egal(2, #demandes)
    egal(true, demandes[2].rapide, 'la demande marquée')
    egal(nil, demandes[1].rapide)
    -- Pendant le travail, la fenêtre dit où en est Claude ; puis sa réponse seule, sans ce qui
    -- précède dans la conversation.
    contient(FenetreRapide.texte(0), 'Claude travaille')
    absent(FenetreRapide.texte(0), 'autre conversation')
    local session = Moteur.session
    repondre('Ciel adouci.')
    egal('Ciel adouci.', FenetreRapide.texte(0), 'la réponse à la demande seulement')
    egal(true, elements(c, 'claude')[2].rapide, 'la réponse marquée')
    egal(nil, elements(c, 'claude')[1].rapide)
    -- Gardée sur le disque, avec ses marques.
    local relue = Stockage.lire(c.id)
    egal(true, relue.elements[#relue.elements - 1].rapide)
    egal(true, relue.elements[#relue.elements].rapide)
    egal('Lac au matin', relue.titre)
    -- Une demande de la fenêtre Claude dans la même conversation : ni marquée, ni montrée par la
    -- Demande rapide ; le même Claude Code (même conversation, modèle, effort et consignes).
    vrai(Moteur.montrer(c))
    vrai(Moteur.envoyer('Et les ombres ?'))
    egal(session, Moteur.session, 'rien de relancé')
    egal('Ciel adouci.', FenetreRapide.texte(0), "pendant le travail de la fenêtre Claude : la réponse d'avant")
    repondre('Ombres relevées.')
    egal('Ciel adouci.', FenetreRapide.texte(0), 'toujours la réponse à la demande rapide')
    egal(nil, elements(c, 'dany')[3].rapide)
    egal(nil, elements(c, 'claude')[3].rapide, 'la réponse de la fenêtre Claude non marquée')
    -- Une autre photo efface la réponse ; la conversation de la photo reste, avec son processus.
    FenetreRapide.cleVue, FenetreRapide.cleVueLe = '501:1:501', os.time() - 10
    FenetreRapide.suivreSelection({ cle = '502:1:502' })
    egal(nil, Moteur.rapide, 'réponse oubliée')
    egal(FenetreRapide.VIDE, FenetreRapide.texte(0))
    egal(nil, Moteur.session.arrete, 'son processus reste (la fenêtre Claude la montre)')
    egal(c, Moteur.conversationDe(501), 'gardée')
    vrai(Fichiers.existe(Stockage.fichier(c.id)))
end)

essai("Photo sans conversation : la demande rapide en crée une avec son historique, la garde ; la fenêtre Claude la reprend et Claude la titre à sa première demande", function()
    local p601 = photo(601)
    journal(p601, { { '2026-10-24 10:00', 'passe 1 : lumière', 'Sous-exposée.' }, { '2026-10-24 10:05', 'balance', 'Dominante bleue.' } })
    photo(602)
    depart({})
    choisir(601)
    local c = Moteur.envoyerRapide('Recadre-la au format 4:5')
    vrai(c, 'la demande rapide')
    egal(601, c.photo, 'la conversation de la photo')
    vrai(not c.rapide, 'pas jetable')
    egal('DSCF0601.RAF', c.titre, 'son titre provisoire')
    egal(nil, c.titreAuto, 'pas encore de titre de Claude')
    local h = elements(c, 'historique')
    egal(1, #h, 'son historique en tête')
    egal('historique', h[1].sorte)
    egal(2, #c.elements, 'son historique, puis la demande')
    egal('historique', c.elements[1].genre)
    egal(true, c.elements[2].rapide)
    egal(true, h[1].envoye, 'joint une seule fois')
    local message = recus[#recus].message
    contient(message, '[Historique de la photo : 2 étapes de Claude')
    contient(message, Consignes.rapidePhoto)
    absent(message, Consignes.rappelTitre)
    egal(nil, recus[#recus].reprise, 'une session neuve')
    egal(c, Moteur.conversationDe(601), 'gardée dès cette demande')
    vrai(Fichiers.existe(Stockage.fichier(c.id)), 'écrite sur le disque')
    vrai(Moteur.courante ~= c, 'pas montrée')
    repondre('Recadrée en 4:5.')
    egal('Recadrée en 4:5.', FenetreRapide.texte(0))
    -- La fenêtre Claude montre la photo : sa conversation revient, sans complément (ce qu'elle a vu
    -- de la photo est relu à la fin du tour) ; sa première demande dans la fenêtre demande le titre.
    Fenetre.suivrePhotos(Lightroom.photos())
    egal(c, Moteur.courante, 'la fenêtre Claude la reprend')
    egal(nil, Historique.depuis(Historique.lire(601), c.vu), "rien de changé depuis ce qu'elle a vu")
    egal(1, #elements(c, 'historique'), 'rien ajouté')
    local session = Moteur.session
    vrai(Moteur.envoyer('Et la balance ?'))
    local fenetre = recus[#recus].message
    contient(fenetre, Consignes.rappelTitre, 'le titre à la première demande de la fenêtre')
    absent(fenetre, 'Historique de la photo', "l'historique déjà envoyé")
    egal(session, Moteur.session, 'le même Claude Code, dans la même session')
    egal(c.id, recus[#recus].conversation)
    repondre('[titre : Pont au matin]\nBalance réchauffée.')
    egal('Pont au matin', c.titre)
    -- La conversation neuve que la fenêtre montre pour une photo (pas encore gardée) : la demande
    -- rapide la prend, sans en faire une autre.
    local neuve = Fenetre.conversationNeuve(602, '602:1:602')
    vrai(Moteur.montrer(neuve))
    choisir(602)
    egal(neuve, Moteur.envoyerRapide('Plus de contraste'), 'celle que la fenêtre montre')
    egal(neuve, Moteur.conversationDe(602))
    vrai(session.arrete, 'une autre conversation : le Claude Code de la 601 fermé')
    egal(nil, recus[#recus].reprise, 'une session neuve pour la 602')
    repondre('Contraste monté.')
    -- Plus tard (Claude Code fermé après inactivité), la Demande rapide sur la 601 reprend sa
    -- session (--resume).
    Moteur.arreterSession()
    choisir(601)
    vrai(Moteur.envoyerRapide('Un peu plus chaud'))
    egal('session-' .. c.id, recus[#recus].reprise, 'la session de la photo reprise')
    egal(c.id, recus[#recus].conversation)
    repondre('Réchauffée.')
end)

essai("Le fil de la fenêtre Claude se met à jour et dit « Demande rapide » sur la demande", function()
    photo(701)
    local c701 = gardee(701, 'Sept cent un')
    depart({ c701 })
    choisir(701)
    local vu = false
    S.pendantFenetre = function()
        vu = true
        egal(c701, Moteur.courante, 'la fenêtre montre la conversation de la photo')
        Fenetre.aRafraichir = false
        vrai(Moteur.envoyerRapide('Adoucis la peau'))
        vrai(Fenetre.aRafraichir, 'la fenêtre se rafraîchit')
        Fenetre.aRafraichir = false
        Fenetre.rafraichir()
        repondre('Peau adoucie.')
        vrai(Fenetre.aRafraichir, 'la réponse aussi')
        Fenetre.rafraichir()
        local p = Fenetre.p
        local mention, reponseVue = 0, false
        for k = 1, 200 do
            local t = p['t' .. k]
            if t == nil then
                break
            end
            if t == Fil.MENTION_RAPIDE then
                mention = mention + 1
            end
            reponseVue = reponseVue or t:find('Peau adoucie.', 1, true) ~= nil
        end
        egal(1, mention, 'une mention, sur la demande rapide seulement')
        vrai(reponseVue, 'la réponse dans le fil')
    end
    local ok, erreur = pcall(Fenetre.afficher)
    S.pendantFenetre = nil
    Fenetre.ouverte = false
    assert(ok, erreur)
    vrai(vu, 'fenêtre ouverte')
    -- La mention : une note sous le texte de la demande, sans caractère nouveau, ni sur la demande
    -- de la fenêtre Claude.
    local lignes = Fil.lignes(c701, Fenetre.largeurTexte())
    local n = 0
    for k, l in ipairs(lignes) do
        if l.texte == Fil.MENTION_RAPIDE then
            n = n + 1
            egal('note', l.genre)
            egal('dany', lignes[k - 1].genre, 'sous le texte de la demande')
            egal(true, c701.elements[l.element].rapide)
        end
    end
    egal(1, n)
end)

essai("La fenêtre Claude, sur une autre photo, suit celle de la demande rapide après son travail, même juste après ; pas pendant", function()
    photo(751)
    photo(752)
    local c751 = gardee(751, 'Sept cent cinquante et un')
    local c752 = gardee(752, 'Sept cent cinquante-deux')
    depart({ c751, c752 }, c751)
    choisir(751)
    Fenetre.voirSelection(Lightroom.photos().cle)
    -- Dany choisit la 752 et clique un bouton de la Demande rapide avant que la fenêtre l'ait vue.
    choisir(752)
    local c = Moteur.envoyerRapide('Plus de contraste')
    egal(c752, c, 'la conversation de la 752')
    egal(c751, Moteur.courante)
    -- Pendant le travail : rien ne change, et la sélection n'est pas prise pour celle de la 751.
    Fenetre.suivreSelection(Lightroom.photos())
    egal(c751, Moteur.courante, 'rien pendant le travail')
    egal(nil, c751.cle, 'la sélection pas donnée à la conversation montrée')
    repondre('Contraste monté.')
    -- Juste après le travail : la fenêtre suit la photo de la demande rapide.
    Moteur.finTravail = os.time()
    Fenetre.suivreSelection(Lightroom.photos())
    egal(c752, Moteur.courante, 'la conversation de la photo choisie par Dany')
    egal(nil, Moteur.selectionRapide, 'une seule fois')
    -- Ensuite, les règles d'avant : une sélection changée juste après un travail de Claude dans la
    -- conversation montrée reste la sienne.
    vrai(Moteur.envoyer('Et la balance ?'))
    repondre('Balance réchauffée.')
    Moteur.finTravail = os.time()
    choisir(751)
    Fenetre.suivreSelection(Lightroom.photos())
    egal(c752, Moteur.courante, 'juste après le travail de la fenêtre Claude : rien ne change')
end)

essai("Plusieurs photos : comme avant, une conversation neuve jamais gardée, avec le résumé court du groupe ; la case Autre photo décochée aussi", function()
    local p801 = photo(801)
    photo(802)
    photo(803)
    journal(p801, { { '2026-10-24 10:00', 'passe 1', 'raison' } })
    local c801 = gardee(801, 'Huit cent un')
    depart({ c801 })
    choisir(801, 802, 803)
    local c = Moteur.envoyerRapide('Harmonise-les')
    vrai(c and c.rapide, 'jetable')
    egal(nil, c.photo)
    contient(Moteur.dossier(c), '/Rapide/', 'ses images en temporaire')
    local message = recus[#recus].message
    contient(message, '[1 de ces 3 photos a déjà des étapes de Claude : DSCF0801.RAF]', 'le résumé court du groupe')
    contient(message, Consignes.rapide)
    egal(nil, recus[#recus].reprise, 'une session neuve')
    for _, x in ipairs(Moteur.conversations) do
        vrai(x ~= c, 'pas parmi les conversations')
    end
    repondre('Harmonisées.')
    egal(false, Fichiers.existe(Stockage.fichier(c.id)), 'jamais écrite')
    egal(1, #elements(c801, 'dany'), "rien dans la conversation d'une photo")
    egal('Harmonisées.', FenetreRapide.texte(0))
    -- Oubliée (une autre sélection) : session arrêtée, dossier effacé.
    Fichiers.creerDossier(c.dossier)
    local session = Moteur.session
    vrai(Moteur.oublierRapide())
    egal(true, session.arrete, 'sa session arrêtée')
    egal(false, Fichiers.existe(c.dossier), 'son dossier effacé')
    -- La case Autre photo décochée : une photo seule aussi dans une conversation jetable.
    prefs.nouvelleParPhoto = false
    choisir(801)
    local seule = Moteur.envoyerRapide('Plus clair')
    prefs.nouvelleParPhoto = true
    vrai(seule and seule.rapide and seule ~= c801, 'case décochée : jetable')
    contient(recus[#recus].message, Consignes.rapide)
    repondre('Éclaircie.')
    egal(1, #elements(c801, 'dany'), 'la conversation de la photo inchangée')
end)

essai("Un seul Claude Code : la Demande rapide refuse pendant que la fenêtre Claude travaille, et inversement", function()
    photo(901)
    photo(902)
    local c901 = gardee(901, 'Neuf cent un')
    depart({ c901 }, c901)
    choisir(901)
    -- La fenêtre Claude travaille.
    vrai(Moteur.envoyer('Retouche pro'))
    local n = #c901.elements
    local recu = #recus
    local c, raison = Moteur.envoyerRapide('Plus doux')
    egal(nil, c)
    egal(Moteur.RAPIDE_TRAVAILLE, raison, 'refusée')
    egal(n, #c901.elements, 'rien ajouté')
    egal(recu, #recus, 'rien envoyé')
    egal(nil, Moteur.rapide)
    FenetreRapide.p = { demande = 'Plus doux' }
    local taches = #S.taches
    FenetreRapide.envoyer()
    egal(taches, #S.taches, 'Envoyer de la Demande rapide sans effet')
    FenetreRapide.p = nil
    repondre('Fait.')
    -- La Demande rapide travaille : la fenêtre Claude refuse.
    choisir(902)
    vrai(Moteur.envoyerRapide('Recadre-la'))
    contient(Moteur.texteTravail(0), 'pour la Demande rapide', 'la fenêtre Claude dit où Claude travaille')
    local ok, refus = Moteur.envoyer('Et la 901 ?')
    egal(false, ok)
    egal(Moteur.CLAUDE_TRAVAILLE, refus, 'refusée')
    local avant = #recus
    Fenetre.envoyer('Et la 901 ?')
    egal(avant, #recus, 'Envoyer de la fenêtre Claude sans effet')
    egal(false, Moteur.montrer(c901), 'ni changer de conversation')
    repondre('Recadrée.')
end)

essai("Un seul Claude Code : la Demande rapide le réserve avant ses lectures du catalogue ; pendant ce temps, la fenêtre Claude n'envoie rien ni ne prend la sélection, et un processus au repos qui s'arrête ne finit rien", function()
    photo(951)
    photo(952)
    local c952 = gardee(952, 'Neuf cent cinquante-deux')
    depart({ c952 }, c952)
    choisir(952)
    -- Une demande finie dans la fenêtre Claude : son Claude Code reste ouvert, au repos.
    vrai(Moteur.envoyer('Retouche pro'))
    repondre('Fait.')
    local auRepos = Moteur.session
    Fenetre.voirSelection('952:1:952')
    local demandes, notes = #elements(c952, 'dany'), #elements(c952, 'note')
    -- Dany choisit la 951 (sans conversation) et clique un bouton de la Demande rapide. Sa lecture du
    -- catalogue (l'historique de la photo) rend la main : la fenêtre Claude tente d'envoyer, suit la
    -- sélection, et le Claude Code au repos s'arrête.
    choisir(951)
    local lire, pendant = S.catalogue.getPhotoByLocalId, nil
    S.catalogue.getPhotoByLocalId = function(cat, id)
        if pendant == nil and tonumber(id) == 951 then
            pendant = {}
            pendant.envoi, pendant.raison = Moteur.envoyer('Et la 952 ?')
            pendant.montree = Moteur.montrer(Conversation.nouvelle())
            Fenetre.suivreSelection(Lightroom.photos())
            pendant.cleVue = Fenetre.cleVue
            Moteur.processusFini(auRepos, 0, '')
            pendant.travaille = Moteur.travaille
        end
        return lire(cat, id)
    end
    local ok, c = pcall(Moteur.envoyerRapide, 'Plus de contraste')
    S.catalogue.getPhotoByLocalId = lire
    assert(ok, c)
    vrai(pendant, 'une lecture du catalogue pendant la demande rapide')
    egal(false, pendant.envoi, 'la fenêtre Claude ne peut pas envoyer')
    egal(Moteur.CLAUDE_TRAVAILLE, pendant.raison)
    egal(false, pendant.montree, 'ni changer de conversation')
    egal('952:1:952', pendant.cleVue, "la sélection n'est pas prise pour celle de la conversation montrée")
    egal(nil, c952.cle, 'ni donnée à sa conversation')
    egal(true, pendant.travaille, "le processus au repos ne finit pas le travail réservé")
    egal(demandes, #elements(c952, 'dany'), 'rien envoyé depuis la fenêtre Claude')
    egal(notes, #elements(c952, 'note'), "aucune note d'arrêt dans sa conversation")
    vrai(c and c.photo == 951, 'la demande rapide part, dans la conversation de la 951')
    egal(c, Moteur.enCours)
    egal(c, Moteur.tourRapide)
    egal(c.id, recus[#recus].conversation)
    contient(recus[#recus].message, 'Plus de contraste')
    repondre('Contraste monté.')
    -- Après son travail, la fenêtre Claude suit la photo choisie par Dany.
    Fenetre.suivreSelection(Lightroom.photos())
    egal(c, Moteur.courante, 'la conversation de la 951')
    -- Et inversement : la fenêtre Claude réserve Claude Code avant ses propres lectures.
    local cible, refus = S.catalogue.getTargetPhoto, nil
    S.catalogue.getTargetPhoto = function(cat)
        if refus == nil then
            refus = select(2, Moteur.envoyerRapide('Plus doux'))
        end
        return cible(cat)
    end
    local okFenetre, envoye = pcall(Moteur.envoyer, 'Et la balance ?')
    S.catalogue.getTargetPhoto = cible
    assert(okFenetre, envoye)
    vrai(envoye)
    egal(Moteur.RAPIDE_TRAVAILLE, refus, 'la Demande rapide refusée pendant les lectures de la fenêtre Claude')
    repondre('Balance réchauffée.')
    -- Une lecture qui échoue rend Claude Code.
    local photos = Lightroom.photos
    Lightroom.photos = function() error('catalogue illisible', 0) end
    local rien, raison = Moteur.envoyerRapide('Plus clair')
    Lightroom.photos = photos
    egal(nil, rien)
    contient(raison, 'catalogue illisible')
    egal(false, Moteur.travaille, 'Claude Code rendu')
    egal(nil, Moteur.tourRapide)
end)

-- Une fenêtre Claude qui préparait la conversation d'une photo choisie quand la Demande rapide s'est
-- réservé Claude Code : refusée, la sélection est suivie après le travail.
essai("La fenêtre Claude qui préparait la conversation d'une photo quand la Demande rapide a réservé Claude Code : la sélection est suivie après son travail", function()
    photo(961)
    photo(962)
    local c962 = gardee(962, 'Neuf cent soixante-deux')
    depart({ c962 }, c962)
    choisir(962)
    Fenetre.voirSelection('962:1:962')
    Moteur.finTravail = os.time() - 60
    choisir(961)
    local lire, rapide = S.catalogue.getPhotoByLocalId, nil
    S.catalogue.getPhotoByLocalId = function(cat, id)
        if rapide == nil and tonumber(id) == 961 then
            rapide = false
            rapide = Moteur.envoyerRapide('Plus de contraste')
        end
        return lire(cat, id)
    end
    local ok, erreur = pcall(Fenetre.suivreSelection, Lightroom.photos())
    S.catalogue.getPhotoByLocalId = lire
    assert(ok, erreur)
    vrai(rapide, 'la demande rapide est partie pendant la préparation')
    egal(c962, Moteur.courante, 'refusée : la conversation montrée reste')
    egal('962:1:962', Fenetre.cleVue, "la sélection n'est pas notée comme vue")
    repondre('Contraste monté.')
    Fenetre.suivreSelection(Lightroom.photos())
    egal(rapide, Moteur.courante, 'après son travail : la conversation de la 961')
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
