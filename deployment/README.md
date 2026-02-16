# Déploiement Automatisé SMS Gateway sur Ubuntu 24.04

Ce dossier contient les fichiers nécessaires pour un déploiement automatisé complet du serveur SMS Gateway avec Zabbix 7.0 LTS.

## 📋 Contenu

- `autoinstall-sms-gateway.yaml` - Fichier autoinstall Ubuntu pour installation automatique
- `README.md` - Ce fichier (documentation)

## 🎯 Ce qui est installé et configuré

### Infrastructure de base
- ✅ Ubuntu 24.04 LTS
- ✅ Réseau statique (10.2.0.203/24)
- ✅ LVM avec disque 1TB (50G root, 500G var, 20G home, 8G swap)
- ✅ Locale FR, timezone Africa/Brazzaville
- ✅ Certificat SSL wildcard `*.congo-handling.aero`

### Stack applicative
- ✅ **Erlang 27.2 + Elixir 1.17.3-otp-27** (via asdf)
- ✅ PostgreSQL 16+ avec bases:
  - `zabbix` (Zabbix)
  - `sms_gateway_prod` (SMS Gateway)
- ✅ Nginx avec SSL/TLS (reverse proxy)
- ✅ Node.js 22.x
- ✅ Phoenix Framework

### Modem Huawei E303/E3372
- ✅ Règles udev pour auto-détection USB
- ✅ usb-modeswitch configuré
- ✅ Permissions groupe `dialout`
- ✅ Script de vérification `/usr/local/bin/check-modem.sh`
- ✅ Monitoring Zabbix Agent2 (signal, réseau, connectivité)

### SMS Gateway
- ✅ Service systemd `/etc/systemd/system/sms-gateway.service`
- ✅ Configuration environnement production
- ✅ URL: `https://cgh-smsg.congo-handling.aero/sms/`
- ✅ Script de déploiement `/opt/sms-gateway/deploy.sh`
- ✅ Migrations Ash/Ecto automatiques
- ✅ Configuration Oban (queue SMS)

### Zabbix 7.0 LTS
- ✅ Zabbix Server + Frontend PHP + Agent2
- ✅ Base PostgreSQL configurée
- ✅ URL: `https://cgh-smsg.congo-handling.aero/`
- ✅ Script d'alertes SMS `/usr/lib/zabbix/alertscripts/sms_api.sh`
- ✅ Monitoring modem intégré

### Sécurité
- ✅ UFW firewall configuré (SSH, HTTP, HTTPS, Zabbix ports)
- ✅ SSL/TLS avec certificats wildcard
- ✅ Headers de sécurité (HSTS, X-Frame-Options, etc.)
- ✅ Service hardening (NoNewPrivileges, PrivateTmp)

## 🚀 Utilisation

### 1. Préparer l'ISO d'installation

```bash
# Télécharger Ubuntu 24.04 Server
wget https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso

# Créer un ISO personnalisé avec autoinstall
# (Voir documentation Ubuntu Autoinstall)
```

### 2. Installation automatique

1. **Monter l'ISO** sur le serveur (VM ou physique)
2. **Booter** depuis l'ISO
3. **Attendre** l'installation automatique (~20-30 minutes)
4. **Redémarrage** automatique à la fin

### 3. Post-installation (première connexion)

```bash
# Se connecter
ssh localadmin@10.2.0.203

# Vérifier le modem
sudo /usr/local/bin/check-modem.sh

# Sortie attendue:
# === Vérification Modem Huawei ===
# [1/5] Périphériques USB Huawei détectés:
#   Bus 001 Device 003: ID 12d1:14db Huawei Technologies Co., Ltd. E303
# [2/5] Interfaces réseau modem:
#   2: usb0: <BROADCAST,MULTICAST,UP,LOWER_UP>
# [3/5] Test connectivité modem (192.168.8.1):
#   ✅ Modem accessible
# [4/5] Test API modem:
#   ✅ API modem répond correctement
# [5/5] Service SMS Gateway:
#   ⚠️  Service inactif (normal avant déploiement)
```

### 4. Déployer l'application SMS Gateway

```bash
# Sur votre machine de développement
cd /Users/dixboss/Developer/sms_gateway

# Compiler la release production
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix assets.deploy  # Si assets présents
MIX_ENV=prod mix release

# Copier la release sur le serveur
scp -r _build/prod/rel/sms_gateway localadmin@10.2.0.203:/opt/sms-gateway/

# Sur le serveur
ssh localadmin@10.2.0.203
cd /opt/sms-gateway
sudo ./deploy.sh

# Sortie attendue:
# === Déploiement SMS Gateway ===
# [1/6] Création de la base de données...
#   ✅ Base de données configurée
# [2/6] Génération des secrets...
#   ✅ Secrets générés
# [3/6] Vérification du modem...
#   ✅ Modem accessible sur 192.168.8.1
# [4/6] Exécution des migrations...
#   ✅ Migrations exécutées
# [5/6] Création API Key admin...
#   API Key: sk_live_abc123...
# [6/6] Démarrage du service...
#   ✅ SMS Gateway démarré avec succès
```

### 5. Vérification du déploiement

```bash
# Status du service
sudo systemctl status sms-gateway

# Logs en temps réel
sudo journalctl -u sms-gateway -f

# Health check API
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

### 6. Créer une API Key pour Zabbix

```bash
# Via IEx console
ssh localadmin@10.2.0.203
cd /opt/sms-gateway
./bin/sms_gateway remote

# Dans IEx:
iex> alias SmsGateway.Sms.ApiKey
iex> Ash.create(ApiKey, %{
...>   name: "Zabbix Alerts",
...>   rate_limit: 1000
...> })

# Copier la clé retournée (sk_live_xxx...)
# Puis configurer dans /usr/lib/zabbix/alertscripts/sms_api.sh
```

### 7. Configuration Zabbix

```bash
# Accéder à Zabbix
# URL: https://cgh-smsg.congo-handling.aero/
# User: Admin
# Password: zabbix (à changer!)

# Configurer le Media Type SMS:
# 1. Administration > Media types > Create media type
# 2. Type: Script
# 3. Script name: sms_api.sh
# 4. Script parameters:
#    {ALERT.SENDTO}
#    {ALERT.SUBJECT}
#    {ALERT.MESSAGE}

# Configurer l'API Key:
sudo nano /usr/lib/zabbix/alertscripts/sms_api.sh
# Remplacer: API_KEY="CHANGE_ME_API_KEY"
# Par: API_KEY="sk_live_xxx_votre_cle"
```

## 🔧 Configuration

### Variables d'environnement SMS Gateway

Les variables sont définies dans `/etc/systemd/system/sms-gateway.service`:

```bash
# Database
DATABASE_URL=ecto://sms_gateway:SmsGateway2024!@localhost/sms_gateway_prod
POOL_SIZE=10

# Phoenix
PORT=4000
PHX_HOST=cgh-smsg.congo-handling.aero
SECRET_KEY_BASE=<généré automatiquement>

# Modem
MODEM_BASE_URL=http://192.168.8.1
MODEM_POLL_INTERVAL=30000  # 30 secondes
MODEM_HEALTH_CHECK_INTERVAL=60000  # 60 secondes

# Oban
OBAN_SMS_SEND_CONCURRENCY=6  # Max 6 SMS simultanés
OBAN_SMS_SEND_RATE_LIMIT=6   # Max 6 SMS/minute

# Rate limiting
DEFAULT_RATE_LIMIT=100  # SMS/heure par API key
```

Pour modifier:
```bash
sudo nano /etc/systemd/system/sms-gateway.service
sudo systemctl daemon-reload
sudo systemctl restart sms-gateway
```

### Changer les mots de passe

```bash
# PostgreSQL SMS Gateway
sudo -u postgres psql
ALTER USER sms_gateway WITH PASSWORD 'NouveauMotDePasse';

# PostgreSQL Zabbix
ALTER USER zabbix WITH PASSWORD 'NouveauMotDePasse';

# Puis mettre à jour:
sudo nano /etc/systemd/system/sms-gateway.service  # DATABASE_URL
sudo nano /etc/zabbix/zabbix_server.conf  # DBPassword
sudo systemctl daemon-reload
sudo systemctl restart sms-gateway zabbix-server
```

## 📊 Monitoring

### Métriques Zabbix disponibles

Le fichier `/etc/zabbix/zabbix_agent2.d/modem-check.conf` définit:

- `modem.signal` - Force du signal (0-100)
- `modem.network` - Type réseau (3G/4G/LTE)
- `modem.connected` - Connectivité modem (0/1)
- `sms_gateway.health` - Health API (0/1)
- `sms_gateway.queue_pending` - Messages en attente

### Logs

```bash
# SMS Gateway
sudo journalctl -u sms-gateway -f

# Zabbix Server
sudo tail -f /var/log/zabbix/zabbix_server.log

# Zabbix Agent
sudo tail -f /var/log/zabbix/zabbix_agent2.log

# Alertes SMS (envois Zabbix)
sudo tail -f /var/log/zabbix/sms_alerts.log

# Nginx
sudo tail -f /var/log/nginx/cgh-smsg-error.log
```

## 🐛 Dépannage

### Le modem n'est pas détecté

```bash
# Vérifier USB
lsusb | grep Huawei

# Forcer le mode modem
sudo usb_modeswitch -v 12d1 -p 1506 -M '55534243123456780000000000000011062000000100000000000000000000'

# Recharger udev
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### L'API modem ne répond pas

```bash
# Ping modem
ping 192.168.8.1

# Test API
curl -v http://192.168.8.1/api/webserver/SesTokInfo

# Vérifier interfaces réseau
ip addr show | grep usb
```

### Le service SMS Gateway ne démarre pas

```bash
# Voir les erreurs
sudo journalctl -u sms-gateway -n 50 --no-pager

# Vérifier PostgreSQL
sudo systemctl status postgresql

# Tester connexion DB
psql -U sms_gateway -d sms_gateway_prod -h localhost

# Vérifier permissions
ls -la /opt/sms-gateway
sudo chown -R localadmin:localadmin /opt/sms-gateway
```

### Les SMS ne sont pas envoyés

```bash
# Vérifier queue Oban
./bin/sms_gateway remote

iex> Oban.check_queue(queue: :sms_send)

# Vérifier circuit breaker
iex> SmsGateway.Modem.Client.reset_circuit_breaker()

# Tester envoi direct
iex> SmsGateway.Modem.Client.send_sms("+33612345678", "Test")
```

## 📝 Différences avec autoinstall.yaml original

### ✨ Améliorations apportées

1. **Erlang/Elixir mis à jour**:
   - Erlang 26.2.1 → **27.2** (OTP 27+ requis)
   - Elixir 1.17.0 → **1.17.3-otp-27**

2. **Support modem Huawei ajouté**:
   - Règles udev pour E303/E3372
   - usb-modeswitch configuré
   - Scripts de vérification et monitoring
   - Zabbix Agent2 checks pour modem

3. **Configuration SMS Gateway améliorée**:
   - Variables d'environnement complètes (Oban, modem, etc.)
   - Script de déploiement avec migrations Ash
   - Service systemd avec hardening
   - Support release Mix moderne

4. **Monitoring Zabbix étendu**:
   - UserParameters pour modem et SMS Gateway
   - Script d'alertes SMS optimisé (201 status code)
   - Logs structurés avec rotation

5. **Dépendances système**:
   - Packages USB ajoutés (usb-modeswitch, libusb, etc.)
   - XML parsing libraries (libxml2, libxslt)

6. **Documentation**:
   - Scripts commentés et documentés
   - Messages de statut explicites
   - Guide de dépannage intégré

## 🔐 Sécurité

### Secrets à changer en production

1. **Mot de passe utilisateur** (`localadmin`)
2. **SECRET_KEY_BASE** (généré auto)
3. **RELEASE_COOKIE** (généré auto)
4. **Database passwords**:
   - `sms_gateway`: SmsGateway2024!
   - `zabbix`: ZabbixSecure2024!
5. **Zabbix admin password**: zabbix
6. **API Keys SMS Gateway**: Créer via IEx

### Recommandations

- ✅ Changer tous les mots de passe par défaut
- ✅ Configurer fail2ban pour SSH
- ✅ Restreindre UFW aux IPs autorisées
- ✅ Activer les mises à jour automatiques de sécurité
- ✅ Configurer des sauvegardes PostgreSQL régulières
- ✅ Surveiller les logs Zabbix pour activités suspectes
- ✅ Renouveler le certificat SSL avant expiration (août 2026)

## 📞 Support

Pour toute question ou problème:
1. Consulter les logs: `sudo journalctl -u sms-gateway -f`
2. Vérifier le modem: `/usr/local/bin/check-modem.sh`
3. Tester l'API: `curl -k https://cgh-smsg.congo-handling.aero/sms/api/health`

## 📚 Ressources

- [Ubuntu Autoinstall](https://ubuntu.com/server/docs/install/autoinstall)
- [Phoenix Framework](https://phoenixframework.org/)
- [Ash Framework](https://ash-hq.org/)
- [Zabbix 7.0 LTS](https://www.zabbix.com/documentation/7.0/)
- [Huawei E303 API](https://github.com/HSPDev/Huawei-E3372-API)
