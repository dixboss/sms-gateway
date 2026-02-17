# Installation SMS Gateway sur Serveur Physique avec Clé USB

Ce guide détaille l'installation automatisée du serveur SMS Gateway sur un **serveur physique** (bare metal) en utilisant une clé USB bootable avec le fichier `autoinstall-sms-gateway.yaml`.

## 📋 Prérequis

### Matériel requis

- **Serveur physique** avec:
  - CPU: 2+ cores (recommandé 4 cores)
  - RAM: 8GB minimum (16GB recommandé)
  - Disque: 1TB SSD/HDD (configuration LVM automatique)
  - Port Ethernet (connexion réseau obligatoire)
  - 2 ports USB libres (1 pour clé USB, 1 pour modem Huawei)

- **Clé USB**: 8GB minimum (pour Ubuntu Server)
- **Modem Huawei**: E303 ou E3372 avec carte SIM active
- **Accès réseau**: DHCP ou adresse IP statique disponible (10.2.0.203/24)

### Logiciels requis (sur votre poste de travail)

**macOS:**
```bash
# Télécharger Ubuntu Server 24.04 LTS
wget https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso

# Installer balenaEtcher pour créer la clé USB bootable
brew install --cask balenaetcher
```

**Linux:**
```bash
# Télécharger Ubuntu Server 24.04 LTS
wget https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso

# Vous utiliserez 'dd' pour créer la clé USB
```

**Windows:**
```powershell
# Télécharger depuis: https://releases.ubuntu.com/24.04/
# Installer Rufus: https://rufus.ie/
```

## 🔧 Étape 1: Préparer la Clé USB Bootable

### Option A: Avec balenaEtcher (macOS/Linux/Windows)

1. **Insérer la clé USB** dans votre ordinateur
2. **Lancer balenaEtcher**
3. **Sélectionner l'ISO**: `ubuntu-24.04-live-server-amd64.iso`
4. **Sélectionner la clé USB** cible
5. **Cliquer "Flash!"** et attendre (~5 minutes)

### Option B: Avec dd (Linux/macOS)

```bash
# Identifier la clé USB
diskutil list  # macOS
lsblk          # Linux

# Exemple: /dev/disk4 (macOS) ou /dev/sdb (Linux)

# Démonter la clé (macOS)
diskutil unmountDisk /dev/disk4

# Démonter la clé (Linux)
sudo umount /dev/sdb*

# Écrire l'ISO sur la clé
sudo dd if=ubuntu-24.04-live-server-amd64.iso of=/dev/disk4 bs=1M status=progress  # macOS
sudo dd if=ubuntu-24.04-live-server-amd64.iso of=/dev/sdb bs=1M status=progress   # Linux

# Attendre la fin (~5-10 minutes)
# NE PAS RETIRER LA CLÉ avant la fin!
```

### Option C: Avec Rufus (Windows)

1. **Lancer Rufus**
2. **Sélectionner le périphérique** (clé USB)
3. **Sélectionner l'ISO**: `ubuntu-24.04-live-server-amd64.iso`
4. **Schéma de partition**: GPT
5. **Système de destination**: UEFI
6. **Cliquer "DÉMARRER"** et attendre

## 📁 Étape 2: Ajouter le Fichier Autoinstall sur la Clé USB

Une fois la clé USB créée, vous devez ajouter le fichier autoinstall pour déclencher l'installation automatique.

### Sur macOS/Linux

```bash
# Remonter la clé USB (elle apparaît comme "Ubuntu 24.04 LTS amd64")
# Le système devrait la monter automatiquement dans /Volumes/ (macOS) ou /media/ (Linux)

# Créer le répertoire pour les fichiers cloud-init
cd /Volumes/Ubuntu\ 24.04\ LTS\ amd64  # macOS
# OU
cd /media/$USER/Ubuntu\ 24.04\ LTS\ amd64  # Linux

# Copier le fichier autoinstall comme user-data
cp /Users/dixboss/Developer/sms_gateway/deployment/autoinstall-sms-gateway.yaml user-data

# Créer un fichier meta-data vide (requis par cloud-init)
touch meta-data

# Vérifier les fichiers
ls -la user-data meta-data

# Sortie attendue:
# -rw-r--r-- 1 user user 40960 Feb 17 10:30 user-data
# -rw-r--r-- 1 user user     0 Feb 17 10:30 meta-data

# Synchroniser et démonter proprement
sync
cd ~
sudo umount /Volumes/Ubuntu\ 24.04\ LTS\ amd64  # macOS
# OU
sudo umount /media/$USER/Ubuntu\ 24.04\ LTS\ amd64  # Linux
```

### Sur Windows

```powershell
# Ouvrir l'Explorateur Windows
# La clé USB apparaît comme "Ubuntu 24.04 LTS amd64"
# Aller à la racine de la clé (ex: E:\)

# Copier le fichier autoinstall
Copy-Item "C:\Users\VotreNom\Downloads\autoinstall-sms-gateway.yaml" "E:\user-data"

# Créer un fichier meta-data vide
New-Item -Path "E:\meta-data" -ItemType File

# Éjecter proprement la clé USB
```

### Vérification

Après avoir ajouté les fichiers, la structure de la clé USB devrait être:

```
/Volumes/Ubuntu 24.04 LTS amd64/
├── boot/
├── casper/
├── ...
├── user-data        ← VOTRE FICHIER AUTOINSTALL
└── meta-data        ← FICHIER VIDE REQUIS
```

**⚠️ IMPORTANT**: Les fichiers `user-data` et `meta-data` doivent être **à la racine de la clé USB**, au même niveau que les dossiers `boot/` et `casper/`.

## 🚀 Étape 3: Démarrer le Serveur depuis la Clé USB

### Préparation du serveur

1. **Éteindre complètement** le serveur
2. **Brancher le modem Huawei** sur un port USB
3. **Insérer la clé USB bootable** sur un autre port USB
4. **Connecter le câble Ethernet** au réseau
5. **Allumer le serveur**

### Accéder au menu de boot

Au démarrage, appuyer sur la touche appropriée pour accéder au **Boot Menu** ou **BIOS**:

| Marque | Touche Boot Menu | Touche BIOS |
|--------|------------------|-------------|
| Dell   | F12              | F2          |
| HP     | F9 ou Esc        | F10         |
| Lenovo | F12              | F1 ou F2    |
| ASUS   | F8               | F2 ou Del   |
| Supermicro | F11          | Del         |
| Generic | F12 ou Esc      | F2 ou Del   |

**Sélectionner** la clé USB dans le menu de boot (ex: "USB HDD: SanDisk").

## ⚙️ Étape 4: Éditer les Paramètres de Boot GRUB (CRITIQUE)

### Pourquoi cette étape est nécessaire?

Par défaut, l'installateur Ubuntu démarre en **mode manuel interactif**. Pour déclencher l'**installation automatique** avec votre fichier `user-data`, vous devez ajouter des paramètres au boot GRUB.

### Écran GRUB attendu

Après avoir sélectionné la clé USB, vous verrez l'écran GRUB suivant:

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│              GNU GRUB  version 2.06                        │
│                                                            │
│ ┌──────────────────────────────────────────────────────┐  │
│ │ *Try or Install Ubuntu Server                        │  │
│ │  Ubuntu Server with the HWE kernel                   │  │
│ │  OEM install (for manufacturers)                     │  │
│ │  Test memory                                         │  │
│ └──────────────────────────────────────────────────────┘  │
│                                                            │
│  Use the ↑ and ↓ keys to select which entry is           │
│  highlighted. Press enter to boot the selected OS,        │
│  'e' to edit the commands before booting, or             │
│  'c' for a command-line.                                  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Instructions détaillées

1. **Attendre 3-5 secondes** que l'écran GRUB apparaisse
2. **Sélectionner "Try or Install Ubuntu Server"** (première option, déjà sélectionnée par défaut)
3. **Appuyer sur la touche `e`** pour éditer les paramètres de boot

Vous verrez alors l'éditeur GRUB:

```
setparams 'Try or Install Ubuntu Server'

   set gfxpayload=keep
   linux /casper/vmlinuz quiet ---
   initrd /casper/initrd

[Éditer et appuyer sur Ctrl+X ou F10 pour démarrer, Esc pour annuler]
```

4. **Naviguer avec les flèches** jusqu'à la ligne commençant par `linux /casper/vmlinuz`
5. **Aller à la fin de cette ligne** (après `quiet ---`)
6. **Ajouter les paramètres suivants** (EXACTEMENT):

```
autoinstall ds=nocloud;s=/cdrom/
```

La ligne complète devrait ressembler à:

```
linux /casper/vmlinuz quiet --- autoinstall ds=nocloud;s=/cdrom/
```

**Explication des paramètres**:
- `autoinstall` → Active le mode installation automatique
- `ds=nocloud;s=/cdrom/` → Indique où trouver les fichiers cloud-init (user-data, meta-data)
  - `ds=nocloud` → Source de données cloud-init de type "nocloud" (fichiers locaux)
  - `s=/cdrom/` → Chemin source (la clé USB est montée comme `/cdrom/`)

7. **Appuyer sur `Ctrl+X` ou `F10`** pour démarrer avec ces paramètres
8. **Attendre 2-3 secondes** → l'écran devrait afficher:

```
[  OK  ] Finished Autoinstall.
[  OK  ] Starting automated installation...
```

### ✅ Vérification: Installation automatique vs manuelle

**Installation AUTOMATIQUE (CORRECT)** - Si vous voyez:
```
Automated Server Install
────────────────────────────────────────────────────
[████████████████████████                    ] 60%
Installing packages...

[  OK  ] Configuring network (static IP: 10.2.0.203)
[  OK  ] Partitioning disk (LVM)
[  OK  ] Installing base system
[  OK  ] Installing PostgreSQL, Nginx, Erlang...
```

**Installation MANUELLE (INCORRECT)** - Si vous voyez:
```
┌─────────────────────────────────────────────────┐
│                                                 │
│  Welcome! This installer will help you          │
│  install Ubuntu Server.                         │
│                                                 │
│  Choose your language:                          │
│  ┌─────────────────────────────────────┐       │
│  │ > English                            │       │
│  │   Français                           │       │
│  │   Deutsch                            │       │
│  └─────────────────────────────────────┘       │
│                                                 │
│          [ Continue ]      [ Back ]             │
└─────────────────────────────────────────────────┘
```

**Si installation manuelle démarre**: Vous avez oublié d'ajouter les paramètres GRUB ou les fichiers user-data/meta-data ne sont pas à la bonne place. **Redémarrez** et recommencez l'Étape 4.

## ⏱️ Étape 5: Attendre l'Installation Automatique

### Durée estimée

- **Téléchargement packages**: 10-15 minutes (selon connexion internet)
- **Installation système**: 5-10 minutes
- **Configuration services**: 5-10 minutes
- **Total**: **20-35 minutes**

### Ce qui est installé automatiquement

1. ✅ **Système de base Ubuntu 24.04** (partitions LVM, locale FR, timezone)
2. ✅ **PostgreSQL 16** (bases zabbix + sms_gateway_prod)
3. ✅ **Nginx** avec certificat SSL wildcard `*.congo-handling.aero`
4. ✅ **Erlang 27.2 + Elixir 1.17.3** (via asdf)
5. ✅ **Zabbix 7.0 LTS** (Server + Frontend + Agent2)
6. ✅ **Support modem Huawei** (udev, usb-modeswitch, monitoring)
7. ✅ **Configuration réseau statique** (10.2.0.203/24)
8. ✅ **UFW Firewall** (SSH, HTTP, HTTPS, Zabbix)
9. ✅ **Scripts de déploiement** SMS Gateway

### Écran pendant l'installation

Vous verrez défiler les logs d'installation:

```
[  OK  ] Starting Initial Setup...
[  OK  ] Configuring locales (fr_FR.UTF-8)
[  OK  ] Setting timezone (Africa/Brazzaville)
[  OK  ] Configuring network interface (ens18: 10.2.0.203/24)
[  OK  ] Installing base packages
[████████████████████████████████████        ] 80%
[  OK  ] Installing PostgreSQL 16
[  OK  ] Creating database: sms_gateway_prod
[  OK  ] Creating database: zabbix
[  OK  ] Installing Zabbix Server 7.0
[  OK  ] Installing Nginx
[  OK  ] Copying SSL certificate (*.congo-handling.aero)
[  OK  ] Installing asdf
[  OK  ] Installing Erlang 27.2 (this may take 10-15 minutes)...
[  OK  ] Installing Elixir 1.17.3-otp-27
[  OK  ] Configuring modem udev rules
[  OK  ] Installing Zabbix Agent2 UserParameters
[  OK  ] Configuring systemd services
[  OK  ] Configuring firewall (UFW)
[  OK  ] Final cleanup
[  OK  ] Installation complete!
         System will reboot in 10 seconds...
```

### Redémarrage automatique

À la fin de l'installation:
1. Le système affiche: `Installation complete! Rebooting in 10 seconds...`
2. **Retirer la clé USB** pendant le redémarrage (ou le serveur bootera à nouveau dessus)
3. Le serveur redémarre sur le disque interne
4. **Attendre 30-60 secondes** pour le boot complet

## 🔍 Étape 6: Première Connexion et Vérification

### Connexion SSH

```bash
# Depuis votre poste de travail
ssh localadmin@10.2.0.203

# Mot de passe: P@ssw0rd (À CHANGER IMMÉDIATEMENT!)
```

**⚠️ SÉCURITÉ**: Changez le mot de passe dès la première connexion:

```bash
passwd
# Entrez: P@ssw0rd (ancien)
# Nouveau mot de passe: [choisir un mot de passe fort]
```

### Vérification du modem

```bash
sudo /usr/local/bin/check-modem.sh
```

**Sortie attendue** (modem connecté):

```
=== Vérification Modem Huawei ===

[1/5] Périphériques USB Huawei détectés:
  Bus 001 Device 003: ID 12d1:14db Huawei Technologies Co., Ltd. E303
  ✅ Modem Huawei détecté

[2/5] Interfaces réseau modem:
  2: usb0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
     inet 192.168.8.100/24 brd 192.168.8.255 scope global usb0
  ✅ Interface réseau configurée

[3/5] Test connectivité modem (192.168.8.1):
  PING 192.168.8.1 (192.168.8.1) 56(84) bytes of data.
  64 bytes from 192.168.8.1: icmp_seq=1 ttl=64 time=2.34 ms
  ✅ Modem accessible

[4/5] Test API modem (SesTokInfo):
  <?xml version="1.0" encoding="UTF-8"?>
  <response>
    <SesInfo>XXX</SesInfo>
    <TokInfo>YYY</TokInfo>
  </response>
  ✅ API modem répond correctement

[5/5] Service SMS Gateway:
  ● sms-gateway.service - SMS Gateway Service
     Loaded: loaded (/etc/systemd/system/sms-gateway.service; enabled)
     Active: inactive (dead)
  ⚠️  Service inactif (normal avant déploiement de l'app)

=== Résumé ===
✅ Modem: OK
✅ API: OK
⚠️  SMS Gateway: Attente déploiement
```

**Si le modem n'est pas détecté**:

```bash
# Vérifier USB
lsusb | grep Huawei

# Débrancher/rebrancher le modem
# Attendre 10 secondes
# Relancer la vérification
sudo /usr/local/bin/check-modem.sh
```

### Vérification des services

```bash
# PostgreSQL
sudo systemctl status postgresql
# État attendu: active (running)

# Nginx
sudo systemctl status nginx
# État attendu: active (running)

# Zabbix Server
sudo systemctl status zabbix-server
# État attendu: active (running)

# Zabbix Agent
sudo systemctl status zabbix-agent2
# État attendu: active (running)

# SMS Gateway (sera inactif avant déploiement)
sudo systemctl status sms-gateway
# État attendu: inactive (dead)
```

### Accéder à l'interface Zabbix

Depuis votre navigateur:

```
URL: https://10.2.0.203/
Utilisateur: Admin
Mot de passe: zabbix
```

**⚠️ SÉCURITÉ**: Changez le mot de passe admin Zabbix immédiatement:
1. User Settings (icône utilisateur en haut à droite)
2. Change password
3. Nouveau mot de passe fort

## 📦 Étape 7: Déployer l'Application SMS Gateway

L'installation du serveur est complète, mais **l'application SMS Gateway n'est pas encore déployée**. Vous devez compiler et déployer l'application Elixir depuis votre machine de développement.

### Sur votre machine de développement

```bash
cd /Users/dixboss/Developer/sms_gateway

# Nettoyer les anciennes compilations
rm -rf _build/prod

# Installer les dépendances production
MIX_ENV=prod mix deps.get --only prod

# Compiler
MIX_ENV=prod mix compile

# Compiler les assets (CSS/JS)
MIX_ENV=prod mix assets.deploy

# Créer la release
MIX_ENV=prod mix release

# Vérifier que la release a été créée
ls -lh _build/prod/rel/sms_gateway/
# Doit contenir: bin/ lib/ releases/ erts-15.2/
```

### Copier la release sur le serveur

```bash
# Créer une archive pour faciliter le transfert
cd _build/prod/rel
tar -czf sms_gateway-release.tar.gz sms_gateway/

# Copier sur le serveur
scp sms_gateway-release.tar.gz localadmin@10.2.0.203:/tmp/

# Se connecter au serveur
ssh localadmin@10.2.0.203
```

### Sur le serveur: Déployer l'application

```bash
# Aller dans le répertoire de déploiement
cd /opt/sms-gateway

# Extraire la release
sudo tar -xzf /tmp/sms_gateway-release.tar.gz -C /opt/sms-gateway/ --strip-components=1

# Ajuster les permissions
sudo chown -R localadmin:localadmin /opt/sms-gateway

# Lancer le script de déploiement
sudo /opt/sms-gateway/deploy.sh
```

**Sortie attendue du script de déploiement**:

```
=== Déploiement SMS Gateway ===

[1/6] Création de la base de données...
  ✅ Base de données 'sms_gateway_prod' existe
  ✅ Utilisateur 'sms_gateway' configuré

[2/6] Génération des secrets...
  ✅ SECRET_KEY_BASE: OBbNy6rF5... (64 caractères)
  ✅ RELEASE_COOKIE: gateway_secret_2024

[3/6] Vérification du modem...
  ✅ Modem accessible sur 192.168.8.1
  ✅ API modem répond

[4/6] Exécution des migrations Ash/Ecto...
  Compiling 127 files (.ex)
  Generated sms_gateway app
  [info] Migrations déjà exécutées (aucune en attente)
  ✅ Migrations à jour

[5/6] Création de l'API Key admin...
  API Key admin créée avec succès!

  ┌──────────────────────────────────────────────────────────┐
  │  IMPORTANT: Copiez cette clé API maintenant!             │
  │  Elle ne sera plus jamais affichée en clair.             │
  │                                                          │
  │  API Key: sk_live_a8f3d9c1e5b                           │
  │  Rate Limit: 1000 SMS/heure                             │
  │                                                          │
  │  Stockez-la dans un gestionnaire de mots de passe!      │
  └──────────────────────────────────────────────────────────┘

[6/6] Démarrage du service...
  ✅ Service systemd rechargé
  ✅ SMS Gateway démarré avec succès

=== Déploiement terminé avec succès! ===

Vérifications:
  • Service: sudo systemctl status sms-gateway
  • Logs: sudo journalctl -u sms-gateway -f
  • Health: curl -k https://cgh-smsg.congo-handling.aero/sms/api/health
```

**⚠️ IMPORTANT**: Copier la clé API affichée! Elle ne sera plus jamais affichée en clair.

### Vérification du déploiement

```bash
# Vérifier le service
sudo systemctl status sms-gateway

# Sortie attendue:
# ● sms-gateway.service - SMS Gateway Service
#    Loaded: loaded (/etc/systemd/system/sms-gateway.service; enabled)
#    Active: active (running) since Mon 2024-02-17 10:45:23 WAT; 30s ago
#  Main PID: 12345 (beam.smp)
#     Tasks: 42 (limit: 9443)
#    Memory: 89.2M
#       CPU: 2.345s
#    CGroup: /system.slice/sms-gateway.service
#            ├─12345 /opt/sms-gateway/erts-15.2/bin/beam.smp...
#            └─12367 erl_child_setup 65536

# Voir les logs en temps réel
sudo journalctl -u sms-gateway -f

# Sortie attendue:
# Feb 17 10:45:23 sms-gateway systemd[1]: Started SMS Gateway Service.
# Feb 17 10:45:25 sms-gateway sms_gateway[12345]: [info] Running SmsGatewayWeb.Endpoint with cowboy 2.12.0 at 0.0.0.0:4000 (http)
# Feb 17 10:45:25 sms-gateway sms_gateway[12345]: [info] Access SmsGatewayWeb.Endpoint at https://cgh-smsg.congo-handling.aero/sms
# Feb 17 10:45:26 sms-gateway sms_gateway[12345]: [info] Modem.StatusMonitor: Circuit breaker closed, modem healthy
# Feb 17 10:45:27 sms-gateway sms_gateway[12345]: [info] Modem.Poller: Polling for incoming SMS (interval: 30s)

# Tester l'API health
curl -k https://cgh-smsg.congo-handling.aero/sms/api/health

# Réponse attendue:
# {
#   "status": "healthy",
#   "modem": {
#     "connected": true,
#     "signal_strength": 85,
#     "network": "Orange F"
#   },
#   "queue": {
#     "pending": 0,
#     "executing": 0
#   },
#   "database": "connected"
# }
```

### Configurer l'API Key pour Zabbix

```bash
# Éditer le script d'alertes Zabbix
sudo nano /usr/lib/zabbix/alertscripts/sms_api.sh

# Remplacer la ligne:
# API_KEY="CHANGE_ME_API_KEY"
# Par:
# API_KEY="sk_live_a8f3d9c1e5b"  # La clé copiée précédemment

# Sauvegarder (Ctrl+O, Entrée, Ctrl+X)

# Tester l'envoi d'un SMS test
/usr/lib/zabbix/alertscripts/sms_api.sh "+242064001234" "Test" "Installation OK"

# Vérifier les logs
sudo tail -f /var/log/zabbix/sms_alerts.log

# Sortie attendue:
# [2024-02-17 10:50:15] INFO: Envoi SMS à +242064001234
# [2024-02-17 10:50:16] SUCCESS: Message accepté (ID: msg_abc123)
```

## ✅ Installation Complète!

Votre serveur SMS Gateway est maintenant opérationnel:

- ✅ **Système**: Ubuntu 24.04 configuré avec réseau statique
- ✅ **Modem**: Huawei E303/E3372 détecté et fonctionnel
- ✅ **Application**: SMS Gateway déployée et active
- ✅ **Monitoring**: Zabbix 7.0 LTS opérationnel
- ✅ **Sécurité**: Firewall UFW actif, SSL configuré

### URLs d'accès

- **Zabbix Frontend**: `https://10.2.0.203/`
- **SMS Gateway API**: `https://cgh-smsg.congo-handling.aero/sms/api/`
- **SMS Gateway Admin**: `https://cgh-smsg.congo-handling.aero/sms/admin`

### Prochaines étapes

1. **Changer tous les mots de passe par défaut** (voir section Sécurité)
2. **Configurer les alertes Zabbix** pour utiliser le SMS Gateway
3. **Créer des API Keys supplémentaires** pour d'autres applications
4. **Mettre en place les sauvegardes PostgreSQL** régulières

Consultez le fichier [`README.md`](README.md) pour plus de détails sur la configuration et le monitoring.

## 🐛 Dépannage

### Le serveur ne boot pas depuis la clé USB

**Cause**: BIOS/UEFI configuré pour Secure Boot ou ordre de boot incorrect

**Solution**:
```
1. Redémarrer et accéder au BIOS (F2/Del)
2. Chercher "Secure Boot" → Désactiver
3. Chercher "Boot Order" → Placer USB en premier
4. Sauvegarder et redémarrer
```

### L'installation démarre en mode manuel (pas automatique)

**Cause**: Paramètres GRUB non ajoutés ou fichiers user-data/meta-data manquants

**Solution**:
```
1. Redémarrer le serveur (Ctrl+Alt+Del)
2. Vérifier que user-data et meta-data sont à la racine de la clé USB
3. Au menu GRUB, appuyer sur 'e'
4. Ajouter "autoinstall ds=nocloud;s=/cdrom/" exactement comme décrit
5. Appuyer sur Ctrl+X
```

### L'installation échoue avec "Cannot download packages"

**Cause**: Pas de connexion internet ou serveur DHCP indisponible

**Solution**:
```
1. Vérifier que le câble Ethernet est branché
2. Vérifier que le routeur/switch est allumé
3. Redémarrer l'installation
4. Si problème persiste: éditer user-data pour changer l'IP statique
```

### Le modem n'est pas détecté après installation

**Cause**: Modem pas branché ou mode stockage USB activé

**Solution**:
```bash
# Vérifier détection USB
lsusb | grep Huawei

# Si aucun résultat: débrancher/rebrancher le modem

# Si détecté comme "Mass Storage" (12d1:1506):
sudo usb_modeswitch -v 12d1 -p 1506 -M '55534243123456780000000000000011062000000100000000000000000000'

# Attendre 10 secondes puis vérifier
sudo /usr/local/bin/check-modem.sh
```

### Le service SMS Gateway ne démarre pas

**Cause**: Release non copiée ou permissions incorrectes

**Solution**:
```bash
# Vérifier que la release existe
ls -la /opt/sms-gateway/bin/sms_gateway

# Si manquant: refaire l'étape 7 (copie de la release)

# Vérifier les permissions
sudo chown -R localadmin:localadmin /opt/sms-gateway

# Vérifier les logs d'erreur
sudo journalctl -u sms-gateway -n 50 --no-pager

# Redémarrer le service
sudo systemctl restart sms-gateway
```

## 📞 Support

Pour toute question ou problème:

1. **Consulter les logs**:
   ```bash
   sudo journalctl -u sms-gateway -f  # Application
   sudo tail -f /var/log/zabbix/zabbix_server.log  # Zabbix
   ```

2. **Vérifier le modem**:
   ```bash
   sudo /usr/local/bin/check-modem.sh
   ```

3. **Tester l'API**:
   ```bash
   curl -k https://cgh-smsg.congo-handling.aero/sms/api/health
   ```

4. **Consulter la documentation complète**: [`README.md`](README.md)

## 📚 Annexes

### A. Alternative: Modifier grub.cfg directement (évite l'édition manuelle)

Si vous souhaitez éviter d'éditer les paramètres GRUB à chaque boot, vous pouvez modifier directement le fichier `grub.cfg` sur la clé USB:

```bash
# Monter la clé USB
cd /Volumes/Ubuntu\ 24.04\ LTS\ amd64  # macOS

# Éditer grub.cfg
nano boot/grub/grub.cfg

# Trouver le menuentry "Try or Install Ubuntu Server"
# Modifier la ligne linux pour ajouter les paramètres:
#   linux /casper/vmlinuz quiet --- autoinstall ds=nocloud;s=/cdrom/

# Sauvegarder et démonter
sync
cd ~
sudo umount /Volumes/Ubuntu\ 24.04\ LTS\ amd64
```

**Avantage**: Installation automatique sans intervention au boot
**Inconvénient**: Plus technique, risque d'erreur de syntaxe

### B. Vérification du fichier user-data avant installation

```bash
# Valider la syntaxe YAML du fichier autoinstall
python3 -c "import yaml; yaml.safe_load(open('autoinstall-sms-gateway.yaml'))"

# Si pas d'erreur: syntaxe correcte
# Si erreur: corriger le fichier avant de le copier sur la clé USB
```

### C. Installation en mode debug (verbose logs)

Pour voir tous les logs d'installation (utile en cas de problème):

Au menu GRUB, ajouter également le paramètre `console=tty0`:

```
linux /casper/vmlinuz autoinstall ds=nocloud;s=/cdrom/ console=tty0
```

Cela affichera tous les logs sur l'écran du serveur pendant l'installation.

---

**Version**: 1.0
**Dernière mise à jour**: 2024-02-17
**Testé sur**: Ubuntu 24.04 LTS Server (Physical Hardware)
