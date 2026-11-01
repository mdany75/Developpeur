# Règles : standard de notation et propose_ratings

Sorti de `Sources/CLAUDE.md` le 31 octobre 2026 ; à lire avant de toucher à `Notation.swift`, aux
plafonds du tri, à `propose_ratings`, à l'échelle des étoiles ou aux libellés de couleur.

- Le standard de notation n'existe qu'à un endroit : `Notation.standard`
  (`Sources/DeveloppeurKit/Notation.swift`). La ressource `developpeur://notation`,
  `propose_ratings` avec `read_standard` et l'invite `noter` le reprennent ; Claude Code dans la
  fenêtre ne lit ni les ressources ni les invites (`--tools ""`, `--disable-slash-commands`) : il
  l'a par `read_standard` seulement (ses consignes l'y renvoient) ; l'invite `noter` (la sélection
  par défaut) sert à Claude Desktop et à Claude Code en terminal. `Notation.plafond` en tire les
  plafonds de `cull_photos` (0 et rejet proposé pour une photo floue, une mise au point manquée, ou
  des yeux fermés quand une autre vue de sa rafale ou de sa pile les a ouverts,
  `PhotoTriee.yeuxOuverts`, `autreVueYeuxOuverts` ; la règle de la rafale, correctif 1.3.4 : sinon
  1, à vérifier, la seule vue de son moment ne se jetant pas pour un clignement, et le tri d'une
  seule photo, la note d'abord de la fenêtre, n'en rejette jamais ; 2 pour une photo douce, à la
  mise au point signalée manquée, ou qui n'est pas la meilleure de sa rafale ; 1, à vérifier, pour
  une photo presque noire ou brûlée, ou une mise au point manquée sur une texture faible, 1.3 ; 1
  pour une capture), que `dernierTri` (`ToolHandler`) garde pour le processus du serveur ; sans
  défaut, aucun plafond sous 5 (« aucun défaut mesuré : pas de plafond », correctif 1.3.2).
  **L'échelle resserrée d'une étoile** (1.4, 26 octobre 2026, demandé par Dany : « je trouve que tu
  notes élevé », « tout baisser d'une étoile », « mais tu peux toujours donner un 5 étoiles ») : 1 ★
  gardée, correcte (l'ancien 1 ★ et l'ancien 2 ★) ; 2 ★ tient seule (l'ancien 3 ★ ; un bon souvenir
  bien fait n'y suffit pas) ; 3 ★ l'impact (l'ancien 4 ★) ; 4 ★ à côté des meilleures (l'ancien 5 ★)
  ; 5 ★ l'exceptionnel, très rare ; dans le doute, la plus basse ; les plafonds descendent d'une
  étoile (ceux d'avant : 3 et 2) ; les notes posées avant gardent l'ancienne échelle ;
  `Fenetre.SENS_NOTES` suit (« Gardée », « Tient seule », « A de l'impact », « Parmi vos meilleures
  », « Exceptionnelle »). Relevé du registre le même soir : sur 345 propositions, 16 % de rejets, 12
  % à 1 ★, 55 % à 2 ★, 16 % à 3 ★, 1 % à 4 ★, dont deux 4 ★ données à des photos de famille notées
  seules, sans avoir vu la sortie. Une scène sur fond noir voulu (L* médian 3,9) reste dite «
  presque noire » : à revoir, hors de la 1.3.
- **Claude note de 0 à 5 ★, jamais un libellé de couleur sans demande** (correctif 1.3.2, demandé
  par Dany le 22 octobre 2026 : « si moi je veux une photo 5 étoiles, je placerai un code de couleur
  ») : `propose_ratings` refuse une note hors de 0 à 5 avant tout envoi (`Notation.noteMaximale =
  5`, 4 jusqu'à la 1.3.1), et le module la refuse encore (`Notation.NOTE_MAX_PROPOSEE = 5`) ; la
  passe 4 (monter à 4, et à 5 pour l'exceptionnel, après le développement, depuis l'échelle
  resserrée de la 1.4) se propose comme les autres. Le standard (section « Les coups de cœur »), les
  descriptions de `propose_ratings` et de `color_label` (`set_metadata`), les invites `noter` et
  `tri_seance`, `ServerInfo.instructions` (« libellé de couleur : sur sa demande ») et
  `Consignes.texte` (« De 0 à 5 ★ ; jamais de libellé de couleur (ses coups de cœur) sans sa
  demande. ») disent que les coups de cœur de Dany sont un libellé de couleur qu'il pose lui-même :
  Claude n'en propose, n'en pose ni n'en change jamais sans sa demande explicite. La carte offre «
  Accepter 5 ★ » (`Fenetre.noteDeCinq` et `Fenetre.PAS_CINQ` retirés). `set_metadata` pose toujours
  une note de 0 à 5 à la demande de Dany, comme Changer… et les étoiles de la carte Note. Jamais
  `set_metadata` pour une note sans demande. `propose_ratings` (titre « Noter des photos ») n'est
  plus en lecture seule depuis la 1.1.1 (hors de `readOnlyTools` : avec `apply`, il écrit dans le
  catalogue) ; il valide toutes les propositions avant d'envoyer quoi que ce soit (les clés de
  chaque élément à la main : `parametresInconnus` ne voit que le premier niveau), refuse une note
  au-dessus du plafond du dernier `cull_photos` sans `to_check`, et envoie une seule commande
  `notation` (`action = 'proposer'`, plus `poser` avec `apply = true`), absente de
  `LightroomBridge.lectures` (rejouée, elle remettrait les propositions « à vérifier »). Plus de
  `session` ni de `read_session` (Séance de notation retirée) ; `pass` est la passe du standard.
