// presse-papiers.js — lit le presse-papiers du Mac pour la fenêtre Claude de Lightroom (le SDK n'y
// a pas accès) : les fichiers d'image copiés dans le Finder (leurs chemins), sinon une image
// copiée (capture d'écran, image de Safari ou d'Aperçu), écrite dans le dossier donné. Une ligne
// par image sur la sortie ; rien s'il n'y a pas d'image. Lit seulement, ne change rien.
//
// Usage : osascript -l JavaScript presse-papiers.js <dossier> [presse-papiers nommé, pour les essais]

ObjC.import('AppKit');

var EXTENSIONS = ['jpg', 'jpeg', 'png', 'heic', 'heif', 'tif', 'tiff', 'webp', 'gif', 'bmp'];
var TYPES = [['public.png', 'png'], ['public.tiff', 'tiff'], ['public.jpeg', 'jpg'], ['public.heic', 'heic']];

function run(argv) {
    var dossier = argv[0];
    var pp = argv.length > 1 && argv[1] ? $.NSPasteboard.pasteboardWithName(argv[1]) : $.NSPasteboard.generalPasteboard;
    var lignes = [];

    var options = $.NSDictionary.dictionaryWithObjectForKey(true, 'NSPasteboardURLReadingFileURLsOnlyKey');
    var urls = pp.readObjectsForClassesOptions($.NSArray.arrayWithObject($.NSURL), options);
    if (urls && !urls.isNil() && urls.count > 0) {
        for (var i = 0; i < urls.count; i++) {
            var chemin = ObjC.unwrap(urls.objectAtIndex(i).path);
            var extension = chemin.split('.').pop().toLowerCase();
            if (EXTENSIONS.indexOf(extension) >= 0) {
                lignes.push(chemin);
            }
        }
        if (lignes.length > 0) {
            return lignes.join('\n');
        }
    }

    for (var t = 0; t < TYPES.length; t++) {
        var donnees = pp.dataForType(TYPES[t][0]);
        if (donnees && !donnees.isNil() && donnees.length > 0) {
            var nom = dossier + '/collee-' + Date.now() + '.' + TYPES[t][1];
            if (donnees.writeToFileAtomically(nom, true)) {
                return nom;
            }
        }
    }
    return '';
}
