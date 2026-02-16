# LogMeIn - Log Management Application

Application de gestion de logs avec pipeline CI/CD complet et infrastructure Docker Swarm.

## Architecture

- **Frontend** : Dashboard HTML/CSS/JS servi par Nginx (reverse proxy vers l'API)
- **Backend** : API Flask (Python 3.11) avec PostgreSQL
- **Base de donnees** : PostgreSQL 15
- **Orchestration** : Docker Swarm (1 manager + 2 workers)
- **CI/CD** : GitHub Actions (CI + CD)
- **Monitoring** : Prometheus + Grafana + cAdvisor + Node Exporter

## Structure du projet

```
LogMeIn/
├── backend/                  # API Flask
│   ├── app.py                # Application principale
│   ├── Dockerfile            # Image Docker du backend
│   ├── requirements.txt      # Dependances Python
│   ├── requirements.dev.txt  # Dependances de test
│   ├── .flake8               # Configuration linting
│   ├── run_tests.sh          # Script d'execution des tests
│   └── tests/                # Tests unitaires (pytest)
├── frontend/                 # Dashboard web
│   ├── index.html            # Interface web
│   ├── style.css             # Styles
│   ├── script.js             # Logique frontend
│   ├── nginx.conf            # Configuration Nginx (reverse proxy)
│   └── Dockerfile            # Image Docker du frontend
├── .github/workflows/        # Pipelines CI/CD
│   ├── ci.yml                # Integration continue
│   └── cd.yml                # Deploiement continu
├── vagrant/                  # Infrastructure Swarm
│   ├── Vagrantfile           # 3 VMs (1 manager + 2 workers)
│   └── scripts/
│       └── install-docker.sh # Provisioning Docker
├── monitoring/               # Stack de monitoring
│   ├── prometheus/
│   │   ├── prometheus.yml    # Configuration Prometheus
│   │   └── alert_rules.yml   # Regles d'alerte
│   ├── grafana/
│   │   └── provisioning/     # Auto-provisioning datasources
│   └── docker-compose.monitoring.yml
├── scripts/                  # Scripts utilitaires
│   ├── deploy.sh             # Deploiement sur Swarm
│   ├── test-ha.sh            # Tests haute disponibilite
│   └── test-scaling.sh       # Tests de scaling
├── docs/                     # Documentation technique
│   └── DOCUMENTATION_TECHNIQUE.md
├── docker-compose.yml        # Developpement local
├── docker-stack.yml          # Production (Swarm)
├── .gitignore
└── README.md
```

## Demarrage rapide

### Developpement local

```bash
# Demarrer tous les services
docker compose up --build

# Acceder au dashboard
# Frontend : http://localhost
# API :      http://localhost:5000
```

### Deploiement Swarm (production)

```bash
# 1. Demarrer le cluster Vagrant
cd vagrant && vagrant up

# 2. Se connecter au manager
vagrant ssh manager

# 3. Deployer l'application
cd /vagrant/../scripts && bash deploy.sh

# 4. Deployer le monitoring
cd /vagrant/../monitoring
docker stack deploy -c docker-compose.monitoring.yml monitoring

# 5. Tester la haute disponibilite
cd /vagrant/../scripts && bash test-ha.sh
```

### Acces aux services

| Service    | URL                       |
|------------|---------------------------|
| Frontend   | http://192.168.56.10      |
| API        | http://192.168.56.10:5000 |
| Prometheus | http://192.168.56.10:9090 |
| Grafana    | http://192.168.56.10:3000 |

## Pipeline CI/CD

Declenchement automatique a chaque push sur `main` ou `develop` :

1. **CI** : Lint (Black, Flake8) -> Tests (pytest + PostgreSQL) -> Build Docker -> Scan securite (Trivy)
2. **CD** : Build & push images (GHCR) -> Deploy staging -> Deploy production (rolling update)

## Securite

- Reseaux overlay chiffres (encrypted: true)
- Docker Secrets pour les mots de passe (pas de variables en clair)
- Conteneurs executes en tant qu'utilisateur non-root
- Scan de vulnerabilites Trivy integre au CI
- Headers de securite Nginx (X-Frame-Options, X-Content-Type-Options, X-XSS-Protection)
- Segmentation reseau : backend-network et frontend-network separes

## API Endpoints

| Methode  | Endpoint      | Description               |
|----------|---------------|---------------------------|
| GET      | /health       | Verification de sante     |
| GET      | /logs         | Liste des logs (pagine)   |
| POST     | /logs         | Ajouter un log            |
| GET      | /stats        | Statistiques des logs     |
| DELETE   | /logs/clear   | Vider tous les logs       |

## Tests

```bash
# Lancer les tests localement
cd backend
pip install -r requirements.txt -r requirements.dev.txt
export DB_HOST=localhost DB_NAME=logs_db DB_USER=logs_user DB_PASSWORD=logs_password DB_PORT=5432
python -m pytest tests/ -v
```
