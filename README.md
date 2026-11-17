# Projet : Synchronisation automatique de KOReader vers Calibre-Web Automated (CWA)

## 1. Objectif du projet

Synchroniser automatiquement la progression de lecture de KOReader, installé sur une PocketBook Verse Pro, vers Calibre-Web Automated (CWA), sans Wi-Fi sur la liseuse et sans activer manuellement le partage de connexion de l'iPhone.

1. L'utilisateur lit normalement sur sa PocketBook avec KOReader.
2. La progression est enregistrée localement sur la liseuse.
3. La liseuse transmet cette progression à l'iPhone par Bluetooth Low Energy (BLE).
4. L'iPhone conserve les données localement.
5. Dès qu'il a Internet, l'iPhone envoie la progression à CWA en HTTPS.

## 2. Matériel et environnement

### Liseuse
- PocketBook Verse Pro, KOReader.
- Linux 3.10.65 (armv7l), firmware de février 2026.
- Puce Bluetooth Realtek 4.2 (`hci0`, UART), BlueZ 5.52 (`bluetoothd -E`).
- Shell KOReader : utilisateur `reader` (uid 101), **pas root**.
- Outils disponibles : `bluetoothctl`, `hciconfig`, `hcitool`, `gatttool`, `dbus-send`.
- La politique D-Bus (`/etc/dbus-1/system.d/bluetooth.conf`) autorise `reader` à parler à `org.bluez`.
- Plugins KOReader présents : `cwasync.koplugin` (fonctionne déjà en Wi-Fi), `kosync.koplugin`, `pocketbooksync.koplugin`, `timesync.koplugin`.

### Téléphone
- iPhone 17, iOS 27.
- Une application iOS personnalisée sera développée.

### Serveur
- Calibre-Web Automated, accessible en HTTPS.
- La synchronisation KOReader de CWA fonctionne déjà avec `cwasync.koplugin`.

## 3. Architecture validée

```text
POCKETBOOK (KOReader)                                    IPHONE                          SERVEUR
plugin blesync.koplugin                                  app iOS
  - enregistre la progression          BLE                 - service GATT                HTTPS
  - file locale (dernière par livre)  ─────▶  écriture  ▶  - file locale      ─────▶  CWA /kosync
  - rôle central : scanne,                                 - vérifie puis envoie
    se connecte, écrit                                       (GET puis PUT)
```

**Le sens est imposé par le matériel** : la liseuse ne peut pas émettre en BLE (voir §4). C'est donc l'iPhone qui expose un service GATT, et la liseuse qui vient s'y connecter pour écrire.

## 4. Résultats des tests sur le matériel réel (2026-11-14)

### Confirmé
| Test | Résultat |
|---|---|
| Scan BLE depuis la liseuse (`reader`) | OK |
| Connexion de la liseuse à l'iPhone (adresse aléatoire du moment) | OK |
| Découverte des services GATT d'une app iOS (LightBlue, service `0x1111`) | OK |
| Lecture d'une caractéristique | OK |
| **Écriture d'une caractéristique** (`48 69` = « Hi », relu à l'identique) | **OK** |
| Appairage liseuse ↔ iPhone | OK (`Paired: yes`) |
| Enregistrement d'un service GATT côté liseuse (`register-application`) | OK, mais inutile sans émission |

### Impossible sur cette liseuse
| Test | Résultat | Cause |
|---|---|---|
| Émission BLE depuis la liseuse (`advertise on`) | `org.bluez.Error.NotPermitted` | `SupportedInstances = 0` : le noyau 3.10 n'a pas l'API d'émission (arrivée avec Linux 4.1) |
| Visibilité BLE en mode « visible » | Invisible depuis un Mac (scan CoreBluetooth de 90 s) | La liseuse n'est visible qu'en Bluetooth classique, inaccessible à une app iOS |
| Partage de connexion iPhone par Bluetooth (PAN/NAP) | `org.bluez.Network1` inexistant | BlueZ compilé sans le module réseau |
| Scan limité au BLE (`SetDiscoveryFilter`) | `NotSupported` | Noyau trop ancien |
| Reconnexion par l'adresse fixe de l'iPhone après appairage | `org.bluez.Error.Failed` | Le noyau ne sait pas relier les adresses temporaires de l'iPhone à son adresse fixe |

### Conséquences
- La liseuse doit **retrouver l'iPhone par scan à chaque synchronisation**, puis se connecter à son adresse du moment (elle change environ toutes les 15 minutes).
- Une app iOS en arrière-plan n'émet plus l'UUID de son service de façon lisible : iOS le cache dans sa « zone de débordement » (données Apple `0x004C`, type `0x01`). La liseuse identifiera donc l'iPhone en **se connectant aux appareils Apple proches, du plus fort signal au plus faible, et en vérifiant la présence du service de l'app**. Elle mémorisera la dernière adresse valide.
- Le service de l'app reste disponible en arrière-plan grâce au mode `bluetooth-peripheral`. Limite iOS : si l'utilisateur ferme l'app de force, iOS ne la relance pas avant qu'il la rouvre.

## 5. Protocole CWA (lu dans `cwasync.koplugin` et `cps/progress_syncing`)

- `PUT /kosync/syncs/progress` avec le corps JSON `{document, progress, percentage, device, device_id}`.
- `GET /kosync/syncs/progress/<document>` renvoie `{document, progress, percentage, device, device_id, timestamp}`.
- `document` est le `partial_md5_checksum` calculé par KOReader (MD5 d'extraits du fichier). CWA garde l'historique des empreintes de chaque livre.
- `percentage` est une fraction entre 0 et 1.
- Authentification HTTP Basic : identifiant et mot de passe envoyés **en clair (base64)** à chaque requête.
- En-tête `Accept: application/vnd.koreader.v1+json`.
- **Le serveur date la progression à la réception** (`datetime.now()`), pas à la lecture.

Conséquences :
- Le mot de passe CWA ne transite jamais par BLE : l'app iOS le garde dans le trousseau iOS et construit elle-même la requête.
- Une progression relayée en retard ne doit pas écraser une lecture plus récente faite ailleurs. L'app fait donc un `GET` avant chaque `PUT`, et n'envoie rien si la progression du serveur est plus récente que l'heure de lecture.

## 6. Contraintes fonctionnelles

- Aucun besoin de Wi-Fi sur la liseuse pendant la lecture.
- Aucun besoin d'activer manuellement le partage de connexion de l'iPhone.
- Conservation locale des progressions tant qu'Internet est indisponible.
- Synchronisation automatique dès qu'Internet est disponible.
- Pas de perte de progression, pas de doublons.
- Compatibilité avec KOReader et avec le CWA existant.

## 7. Contrat BLE

| Élément | Valeur |
|---|---|
| Service | `947694FE-0425-4E30-84BC-FB783E781EAD` |
| Caractéristique `progress` | `1FD42B59-27A4-49F9-B36B-C1D0F9C445B2` |
| Propriétés | Écriture avec réponse, sans chiffrement : le noyau ne relie pas les adresses tournantes de l'iPhone à son appairage, une liaison chiffrée serait refaite à chaque fois. Les données (position de lecture) ne sont pas sensibles. |
| Accusé de réception | La réponse à l'écriture. La liseuse ne retire l'entrée de sa file qu'après une écriture réussie. |

Contenu écrit (JSON UTF-8, environ 250 octets, envoyé en écriture longue) :

```json
{
  "v": 1,
  "document": "9e107d9d372bb6826bd81d3542a419d6",
  "progress": "/body/DocFragment[12]/body/div/p[34]/text().56",
  "percentage": 0.4567,
  "device": "PocketBook Verse Pro",
  "device_id": "<device_id KOReader>",
  "captured_at": 1794680000,
  "sent_at": 1794680582
}
```

`captured_at` et `sent_at` viennent de l'horloge de la liseuse, qui peut être décalée faute de Wi-Fi. L'app iOS calcule donc l'heure réelle de lecture à partir de sa propre horloge : `heure de réception − (sent_at − captured_at)`. Seul l'écart entre les deux horodatages compte, pas leur valeur absolue.

## 8. Plan du prototype

Chaque phase se termine par une vérification sur le matériel réel avant de passer à la suivante.

### Phase 0 — Lever les dernières inconnues côté liseuse (tests en shell, sans code)
- ✅ Allumer et éteindre le Bluetooth sans passer par l'interface PocketBook : `/ebrmain/bin/netagent bt on` / `bt off` fonctionnent depuis `reader` (2026-11-15). `bt on` lance `bluetoothd` ; `bt off` arrête `bluetoothd` et `rtk_hciattach`, et `hci0` disparaît. Le script de synchronisation allume donc le Bluetooth au début et l'éteint à la fin. (`bluetoothctl power off/on` marche aussi, mais coupe seulement la radio.)
- ✅ Veille : on considère qu'aucun processus ne tourne pendant la veille (la liseuse semble s'éteindre). Inutile de tester plus : la file locale rend toute synchro interrompue sans conséquence.
- ✅ Écriture longue : 258 octets arrivés entiers dans LightBlue en une seule écriture (2026-11-16, [`poc/test3-long-write.sh`](poc/test3-long-write.sh)). Pas de découpage côté liseuse. BusyBox n'a pas `od -An -tx1` : convertir en hex avec `hexdump -v -e '/1 "0x%02x "'`.

### Phase 1 — Plugin KOReader, sans Bluetooth
- `blesync.koplugin` enregistre la progression dans sa file à la fermeture du livre, à la mise en veille et toutes les N pages.
- Il lance la synchro au réveil, à la fermeture du livre et toutes les N pages, jamais à la mise en veille (aucun processus ne survit à la veille).
- Récupère `document` (`partial_md5_checksum`), `progress`, `percentage` et `device_id`, comme le fait `cwasync`.
- File locale (fichier de réglages KOReader) qui ne garde que la dernière entrée par livre.
- Vérification : la file contient les bonnes valeurs sur de vrais livres, et elles correspondent à ce qu'envoie `cwasync`.
- ✅ Installé sur la liseuse (2026-11-16) : la file affiche une entrée par livre (menu « BLE sync: show queue »). Empreinte et position calculées avec le même code que `cwasync`.

> Phases 2 à 4 implémentées d'un bloc le 2026-11-16 (à la demande de l'utilisateur), pour un seul passage de tests sur le matériel. Code : `blesync.koplugin/` (plugin + `blesync.sh`) et `ios/` (app iOS, projet Xcode).

### Phase 2 — Transport BLE depuis la liseuse
- Script shell lancé en arrière-plan par le plugin, pour ne pas bloquer l'interface. Il réutilise les commandes `bluetoothctl` déjà validées :
  1. allumer le Bluetooth ;
  2. scanner ;
  3. essayer d'abord la dernière adresse valide, puis les appareils Apple par signal décroissant ;
  4. vérifier la présence du service ;
  5. écrire ;
  6. se déconnecter ;
  7. éteindre le Bluetooth.
- Le résultat est écrit dans un fichier, que le plugin relit pour vider sa file.
- Vérification avec LightBlue au premier plan, configurée avec le service et la caractéristique du contrat.

- ✅ Liseuse → app iOS validé sur le matériel (2026-11-16) : progression reçue et stockée par l'app au premier plan, en 16 s.
  - Au premier plan, l'app s'annonce sous le nom `BLESync` : c'est ainsi que le script la repère, car `bluetoothctl` n'affiche pas les UUID annoncés d'un appareil nouvellement découvert.
  - L'iPhone utilise une adresse différente par jeu d'annonces : l'adresse « Apple » vue au scan n'est pas forcément celle de l'app.
  - Envoi par `gatttool` (et non `bluetoothctl`) : `bluetoothd` lisait d'office des services chiffrés de l'iPhone (batterie, infos appareil), ce qui affichait « Pair » à chaque synchro. Avec `gatttool`, plus de demande d'appairage, confirmation explicite (`written successfully`), synchro complète en 13 s (10 s de scan + 3 s).

### Phase 3 — App iOS : réception
- SwiftUI minimal, `CBPeripheralManager` avec le service du contrat, mode d'arrière-plan `bluetooth-peripheral` et restauration d'état.
- Stockage local, en ne gardant que la dernière entrée par `document`.
- Écran de liste des progressions reçues, pour le diagnostic.
- Vérification : écriture depuis la liseuse, l'app au premier plan.

### Phase 4 — App iOS : envoi vers CWA
- Réglages : URL CWA, identifiant et mot de passe dans le trousseau iOS.
- À chaque réception, et quand le réseau revient : `GET` de la progression ; si le serveur est plus récent que l'heure de lecture, l'entrée est abandonnée ; sinon `PUT`. L'entrée est retirée après une réponse 2xx.
- Une réponse 401 s'affiche dans l'app ; une erreur réseau déclenche une nouvelle tentative plus tard.
- Vérification : la progression apparaît dans l'interface web de CWA, et une progression plus récente faite ailleurs n'est pas écrasée.

- ✅ Chaîne complète validée (2026-11-16), app au premier plan : liseuse → app iOS → CWA (`GET` puis `PUT`), progression visible dans CWA.

### Phase 5 — Tests réels en arrière-plan
- iPhone verrouillé en poche, app en arrière-plan, puis suspendue par iOS.
- Cycles de veille de la liseuse, iPhone hors de portée puis de retour, Internet coupé puis rétabli.

- ✅ App en arrière-plan (2026-11-16) : iPhone trouvé comme 1er appareil Apple candidat (pas de nom `BLESync` annoncé), écriture en 5 s, synchro liseuse ≈ 15 s ; l'app a reçu et envoyé à CWA 2 s plus tard.
- Reste à tester : app suspendue depuis des heures puis relancée par iOS (restauration d'état), lieu avec beaucoup d'appareils Apple (l'iPhone peut sortir des 5 candidats), Internet coupé puis rétabli.

### Phase 6 — Fiabilisation
- Reprise après une écriture interrompue, gestion des déconnexions, tentatives espacées, consommation de batterie de la liseuse.

### Hors du premier jet
- Rapatrier sur la liseuse la progression lue sur un autre appareil, à l'ouverture d'un livre.

## 9. Consignes pour Claude Code

1. Les résultats du §4 sont acquis : ne pas refaire ces tests.
2. Réutiliser le protocole CWA existant (§5) ; ne pas inventer d'endpoint.
3. Avancer phase par phase (§8). Exception : les phases 2 à 4 ont été écrites d'un bloc et se testent ensemble.
4. Demander les informations manquantes (URL CWA, identifiants) plutôt que de les supposer.
