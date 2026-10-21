-- gabarits.lua — écrit sur la sortie standard, en JSON, ce que scripts/images-fenetre.swift dessine
-- (Dispositions.gabarits) : la taille en points de chaque image de la fenêtre Claude
-- (Dispositions.IMAGES, leur seule source), puis, pour chaque apparence (claire et sombre), le
-- dossier de ses images et sa palette (Dispositions.PALETTES, seule source des couleurs) :
-- { "images": { "<nom>": { "largeur": …, "hauteur": … } },
--   "apparences": { "<apparence>": { "dossier": "images…", "couleurs": { "<clé>": "RRGGBB" } } } }.
-- Charge Dispositions.lua sous LuaJIT, hors de Lightroom (Vues et Consignes, qu'il requiert, se
-- chargent sans import), et écrit par Json.lua du module, comme tout le JSON du projet. Ne lit ni
-- n'écrit aucun fichier.
--
-- Usage : luajit scripts/gabarits.lua | swift scripts/images-fenetre.swift Lightroom/Developpeur.lrplugin

local scripts = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
local module = scripts .. '/../Lightroom/Developpeur.lrplugin'
package.path = module .. '/?.lua;' .. package.path

local Dispositions = require 'Dispositions'
local Json = require 'Json'

io.write(Json.encode(Dispositions.gabarits()), '\n')
