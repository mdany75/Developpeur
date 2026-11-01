# Module Lightroom : avant/après des étapes

Sorti de `Lightroom/CLAUDE.md` le 31 octobre 2026 (qui y renvoie) ; à lire avant de toucher à
`Etapes.lua`, à `Ecriture.nouvelleEtape`, à `Liaison.recevoir` ou à la capture de l'avant/après.

- **L'avant/après d'une étape se garde au rendu, jamais par une écriture** (1.3, `Etapes.lua` ;
  `docs/SPEC.md`, Pourquoi ?) : Lightroom ne rend que l'état actuel. Toute étape nouvelle passe par
  `Ecriture.nouvelleEtape` (`{ id, nom, avant, le }`, id par `Ecriture.idEtape`) ; `etape_id`
  (résultats, journal, `annuler`) n'est pas un réglage ; une étape d'avant la 1.3, sans id,
  s'annule par son rang. La capture se fait autour de la commande (`Liaison.recevoir` :
  `Etapes.avantCommande`, `apresCommande` une fois la réponse partie, `abandonner` ; ces crochets
  ne laissent passer aucune erreur) : case Avant/après et fenêtre ouverte ou son Claude au travail
  (`Etapes.actifPour`), ou `avant_apres` (la recette seulement, jamais un outil) ; une seule
  photo, la photo active ; jamais `sans_avant_apres` (`match_series` l'envoie), ni en pause, ni
  pour un refus prévisible ; jamais un rendu avec des calculs IA en attente. L'avant est la vue
  (`Rendu.apercu` ne la garde que pour l'image entière de l'état actuel, jamais un zoom, un
  `chemin_avant`, un `essayer` ni une image entière de la composition) reconnue par l'empreinte,
  sinon un rendu avant l'écriture ; l'après est rendu après la réponse. Une capture à la fois
  (`ATTENTE` 8 s pour les commandes hors `SANS_ATTENTE`, `PERIMEE` 120 s) ; `COTE` 1 024. Dans
  l'empreinte (`sansVolatils`), une table vide sous une clé texte vaut une clé absente (constaté le
  21 octobre 2026 : `MaskGroupBasedCorrections` absente ↔ `{}` après une comparaison, une
  annulation de masque, les rendus du recalage) ; Lightroom ne change seul aucune clé (constaté).
  Captures de 0,51 à 1,06 s, réponse +4 % avec une vue, +0,8 s sans ; ménage au chargement
  (`Etapes.menage`, 30 jours, 500 Mo).
