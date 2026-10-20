-- MenuDemarrer.lua : Fichier (ou Bibliothèque) › Module externe - Extras › Démarrer la liaison avec Claude

local LrDialogs = import 'LrDialogs'

local Liaison = require 'Liaison'

Liaison.demarrer()
LrDialogs.showBezel("Liaison avec Claude démarrée")
