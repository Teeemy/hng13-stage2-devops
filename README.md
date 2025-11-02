# Blue-Green Deployment with Nginx

## 🔗 HNG Internship

This project is part of the HNG13 DevOps Internship program.

- Learn more: [HNG Internship](https://hng.tech/internship)
- Hire talented developers: [HNG Hire](https://hng.tech/hire)

## 📁 Folder Structure

```
hng13-stage2-devops/
├── .github/
│   └── workflows/
│       └── blue-green-test.yml
├── .env
├── .env.example
├── docker-compose.yml
├── nginx.conf
├── Devops_research.md
├── reload_nginx.sh
└── README.md
```

## 🚀 Quick Start

### 1. Clone and Setup

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your values
nano .env
```

### 2. Start Services

```bash
# Start all services
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

### 3. Test Deployment

```bash
# Make script executable
chmod +x reload_nginx.sh

# Test basic reload
./reload_nginx.sh

# Test with failover verification
./reload_nginx.sh --test
```

## 🔧 Configuration

### Environment Variables (.env)

```properties
BLUE_IMAGE=teemy01/hng-node-app:latest
GREEN_IMAGE=teemy01/hng-node-app:latest
ACTIVE_POOL=blue
RELEASE_ID_BLUE=v1.0.0-blue
RELEASE_ID_GREEN=v1.0.0-green
PORT=8080
NGINX_PORT=8080
BLUE_PORT=8081
GREEN_PORT=8082
```

## 🧪 Testing

### Manual Testing

```bash
# Check version endpoint
curl http://localhost:8080/version

# Trigger chaos on Blue
curl -X POST http://localhost:8081/chaos/start?mode=error

# Verify failover to Green
curl http://localhost:8080/version

# Stop chaos
curl -X POST http://localhost:8081/chaos/stop
```

### Automated Testing

```bash
# Run full failover test
./reload-nginx.sh --test
```

### Expected Behavior

1. **Before Chaos**: All requests return `X-App-Pool: blue`
2. **After Chaos**: Requests automatically fail over to `X-App-Pool: green`
3. **Zero Downtime**: All responses return HTTP 200

## 📊 Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| Nginx (Public) | http://localhost:8080 | Main entry point |
| Blue (Direct) | http://localhost:8081 | Blue pool (chaos testing) |
| Green (Direct) | http://localhost:8082 | Green pool (chaos testing) |

### Available Routes

- `GET /version` - Returns pool and release info
- `GET /healthz` - Health check endpoint
- `POST /chaos/start?mode=error` - Simulate errors (500s)
- `POST /chaos/start?mode=timeout` - Simulate timeouts
- `POST /chaos/stop` - Stop chaos simulation

## 🔄 Switching Active Pool

1. Edit `.env` and change `ACTIVE_POOL=green`
2. Run `./reload-nginx.sh` to apply changes
3. Optionally add `--test` flag to verify

## 🎯 CI/CD

GitHub Actions workflow automatically:
- Sets up environment
- Pulls Docker images
- Starts services
- Runs verification tests
- Tears down on completion

Trigger manually or on push to main/develop branches.

## ⚙️ Nginx Configuration

The Nginx config uses:
- **Primary/Backup upstreams**: Blue is primary, Green is backup
- **Fast failover**: 3s connection timeout, 5s read timeout
- **Automatic retry**: Retries on error/timeout/5xx within same request
- **Health checks**: 2s timeouts on `/healthz`
- **Header forwarding**: `X-App-Pool` and `X-Release-Id` passed unchanged

## 🐛 Troubleshooting

### Services won't start
```bash
docker compose logs
docker compose ps -a
```

### Failover not working
- Check Nginx config: `docker compose exec nginx nginx -t`
- Verify timeouts are appropriate
- Check app logs: `docker compose logs blue green`

### Port conflicts
- Change ports in `.env`
- Restart services: `docker compose down && docker compose up -d`

## 📝 Requirements Met

- ✅ Docker Compose orchestration
- ✅ Nginx with Blue/Green failover
- ✅ Parameterized via .env
- ✅ Direct port access (8081, 8082)
- ✅ Zero downtime failover
- ✅ Header forwarding (X-App-Pool, X-Release-Id)
- ✅ Automated testing script
- ✅ CI/CD pipeline
- ✅ No image builds required
- ✅ Request timeout < 10s

## 🔐 Security Notes

- Images pulled from public registry
- No sensitive data in repository
- Environment variables for configuration
- Logs available for debugging

## 📚 Additional Resources

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Nginx Upstream Module](http://nginx.org/en/docs/http/ngx_http_upstream_module.html)
- [Blue-Green Deployment Pattern](https://martinfowler.com/bliki/BlueGreenDeployment.html)


## 👤 Author

**Onibonoje Mariam T**
- GitHub: [@Teeemy](https://github.com/Teeemy)
- Slack: @Mayreeharm