-- MenuArreter.lua : Fichier (ou Bibliothèque) › Module externe - Extras › Arrêter la liaison avec Claude

local LrDialogs = import 'LrDialogs'

local Liaison = require 'Liaison'

Liaison.arreter()
LrDialogs.showBezel("Liaison avec Claude arrêtée")
