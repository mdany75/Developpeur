-- essais-reimportation.lua : une livraison réimportée (exporter avec reimporter = 'pile'), quand
-- Lightroom l'ajoute au catalogue et l'empile bien après le rendu. Constaté le 10 novembre 2026
-- (Lightroom Classic 16.0, très occupé par un tri assisté de 20 000 photos) : la recette a exporté
-- DSCF2402.tif à côté de l'original, mais le TIFF n'était pas encore au catalogue au bout des 10 s
-- d'attente du module, ni plusieurs minutes plus tard ; une heure avant, la photo trouvée n'était
-- pas encore empilée. Simulé par S.delaiReimport et S.delaiEmpilement (Simulation.lua).
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, echoue = A.test, A.egal, A.echoue

local Commandes = require 'Commandes'
local Livraison = require 'Livraison'
local Photos = require 'Photos'

-- Un chemin propre à chaque essai : reimporteesSession (Livraison.lua) vit tout le temps des essais
-- et S.reinitialiser ne le vide pas ; un chemin partagé laisserait un essai profiter de
-- l'inscription d'un autre (l'inscription dès l'exportation ne serait plus gardée).
local DOSSIER = '/Volumes/Photos/2025/Gaspesie/'

local function original(nom)
    local photo = A.photoFuji()
    photo.brut.path = DOSSIER .. nom .. '.RAF'
    photo.meta.fileName = nom .. '.RAF'
    S.active, S.selection = photo, { photo }
    S.fichiers['/Volumes/Photos'] = 'dossier'
    return photo, DOSSIER .. nom .. '.tif'
end

local function livrer(reimporter)
    local reglages = { format = 'TIFF', reimporter = reimporter or 'pile' }
    if reimporter == false then
        reglages.reimporter = nil
    end
    return Commandes.executer('exporter', { photos = { 4 }, dossier = reimporter ~= 'pile' and '/Volumes/Photos/Imprimerie' or nil,
        reglages = reglages })
end

test("l'attente de la réimportation reste sous la réponse d'attente de 50 s du serveur", function()
    egal(Livraison.ATTENTE_REIMPORT >= 30 and Livraison.ATTENTE_REIMPORT < 50, true, "attente : " .. tostring(Livraison.ATTENTE_REIMPORT))
end)

test("réimportée 15 s après le rendu : trouvée, et empilée avec l'original", function()
    local photo, chemin = original('XH2S0320')
    S.delaiReimport, S.delaiEmpilement = 15, 3
    local debut = S.horloge
    local fichier = livrer().fichiers[1]
    egal(fichier.chemin, chemin)
    egal(type(fichier.reimportee), 'number', "trouvée après 15 s")
    egal(fichier.empilee, true, "attendue jusqu'à l'empilement")
    egal(S.photos[fichier.reimportee].empileeAvec, photo)
    egal(fichier.pas_encore_au_catalogue, nil)
    egal(fichier.pas_encore_empilee, nil)
    egal(S.horloge - debut < 25, true, "rien d'attendu de plus que l'empilement")
end)

test("trouvée mais empilée trop tard : marquée pas encore empilée", function()
    original('XH2S0321')
    S.delaiReimport, S.delaiEmpilement = 2, 120
    local fichier = livrer().fichiers[1]
    egal(type(fichier.reimportee), 'number')
    egal(fichier.empilee, nil)
    egal(fichier.pas_encore_empilee, true)
end)

test("réimportée trop tard : réponse « pas encore au catalogue », puis retirée par retirerReimportees", function()
    local _, chemin = original('XH2S0322')
    S.delaiReimport, S.delaiEmpilement = 90, 1
    local debut = S.horloge
    local resultat = livrer()
    local fichier = resultat.fichiers[1]
    egal(fichier.chemin, chemin, "le fichier est livré à côté de l'original")
    egal(fichier.reimportee, nil)
    egal(fichier.pas_encore_au_catalogue, true)
    egal(S.horloge - debut >= Livraison.ATTENTE_REIMPORT, true, "attendu " .. Livraison.ATTENTE_REIMPORT .. " s")
    egal(S.horloge - debut < 50, true, "rendu avant la réponse d'attente du serveur")
    -- Pas encore là : rien à retirer, mais le fichier reste celui de Claude (pas de refus).
    local tot = Commandes.executer('retirerReimportees', { chemins = { chemin } })
    egal(#tot.retires, 0)
    egal(tot.pas_au_catalogue[1], chemin)
    -- Arrivé plus tard : retiré du catalogue.
    S.horloge = S.horloge + 120
    local photo = Photos.catalogue():findPhotoByPath(chemin)
    egal(photo ~= nil, true, "Lightroom l'a ajouté plus tard")
    local retrait = Commandes.executer('retirerReimportees', { chemins = { chemin } })
    egal(retrait.retires[1], chemin)
    egal(#retrait.pas_au_catalogue, 0)
    egal(S.retireesDuCatalogue[#S.retireesDuCatalogue].localIdentifier, photo.localIdentifier)
    echoue(function() Commandes.executer('retirerReimportees', { chemins = { chemin } }) end, "pas été réimporté")
end)

test("arrivée tard : inscrite dès l'exportation, listée pour la recette (lister), sans rien retirer", function()
    local _, chemin = original('XH2S0323')
    S.delaiReimport, S.delaiEmpilement = 90, 1
    local avant = Commandes.executer('retirerReimportees', { lister = true }).inscrits
    for _, inscrit in ipairs(avant) do
        egal(inscrit ~= chemin, true, "pas inscrit avant l'exportation")
    end
    egal(livrer().fichiers[1].pas_encore_au_catalogue, true)
    local apres = Commandes.executer('retirerReimportees', { lister = true }).inscrits
    local trouve = false
    for _, inscrit in ipairs(apres) do
        trouve = trouve or inscrit == chemin
    end
    egal(trouve, true, "inscrit dès l'exportation, avant son arrivée au catalogue")
    egal(#S.retireesDuCatalogue, 0, "lister ne retire rien")
    egal(#Commandes.executer('retirerReimportees', { chemins = { chemin } }).pas_au_catalogue, 1)
end)

test("livraison sans réimportation : aucune attente, aucune marque", function()
    original('XH2S0324')
    S.delaiReimport, S.delaiEmpilement = 90, 90
    local debut = S.horloge
    local fichier = livrer(false).fichiers[1]
    egal(fichier.chemin, '/Volumes/Photos/Imprimerie/XH2S0324.tif')
    egal(S.horloge - debut < 5, true, "attendu " .. (S.horloge - debut) .. " s sans réimportation")
    egal(fichier.reimportee, nil)
    egal(fichier.pas_encore_au_catalogue, nil)
    egal(fichier.pas_encore_empilee, nil)
end)

test("réimportée au catalogue sans pile (catalogue) : trouvée, sans attendre d'empilement", function()
    original('XH2S0325')
    S.delaiReimport, S.delaiEmpilement = 2, 90
    local debut = S.horloge
    local fichier = livrer('catalogue').fichiers[1]
    egal(fichier.chemin, '/Volumes/Photos/Imprimerie/XH2S0325.tif')
    egal(type(fichier.reimportee), 'number')
    egal(fichier.pas_encore_empilee, nil, "pas de pile demandée")
    egal(fichier.empilee, nil)
    egal(S.horloge - debut < 10, true, "attendu " .. (S.horloge - debut) .. " s : la seule arrivée au catalogue")
end)

A.bilan()
