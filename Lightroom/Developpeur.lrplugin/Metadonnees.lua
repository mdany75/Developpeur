-- Metadonnees.lua : champs du module enregistrés dans le catalogue, pour chaque photo.
-- Sans titre, un champ reste privé (invisible dans le panneau Métadonnées).

return {
    metadataFieldsForPhotos = {
        -- Valeur d'origine de chaque réglage touché par Claude (JSON).
        { id = 'avantClaude', dataType = 'string' },
        -- Dernières retouches de Claude, avec les valeurs qu'elles ont remplacées (JSON).
        { id = 'etapesClaude', dataType = 'string' },
        -- Journal des retouches de Claude : date, étape, raison, changements (JSON). Il reste
        -- après un retour à l'état d'avant Claude.
        { id = 'journalClaude', dataType = 'string' },
        -- Visible et filtrable dans la Bibliothèque.
        {
            id = 'retoucheeParClaude',
            title = "Retouchée par Claude",
            dataType = 'string',
            readOnly = true,
            searchable = true,
            browsable = true,
        },
        -- uuid de la photo à qui appartiennent les champs ci-dessus : Lightroom les copie dans une
        -- copie virtuelle (voir « Propriétaire de la mémoire » dans Photos.lua).
        { id = 'proprietaireMemoire', dataType = 'string' },
        -- Variantes rangées en instantanés : les réglages que chacune touche (JSON).
        { id = 'variantesClaude', dataType = 'string' },
        -- État où la dernière commande de Claude a laissé la photo (JSON) : ce que l'utilisateur
        -- a changé depuis se lit par différence (Ecriture.correctionsUtilisateur).
        { id = 'apresClaude', dataType = 'string' },
        -- « oui » : Lightroom compte la photo comme exportée (isExported) seulement parce que Claude
        -- l'a rendue en aperçu (constaté en 2.4 : un aperçu passe par LrExportSession) ; une
        -- livraison de Claude l'efface. Pas une mémoire de Claude : un retour à l'origine le garde.
        { id = 'apercuSeulement', dataType = 'string' },
    },
    -- 1 : Développeur 1.0. Nouvel identifiant de module : rien n'est repris des champs de l'ancien
    -- connecteur (une photo qu'il a retouchée n'a pas de mémoire ici).
    schemaVersion = 1,
}
