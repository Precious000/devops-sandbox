.PHONY: up down create destroy logs health simulate clean

PLATFORM=platform
ENV ?= ""
MODE ?= crash
NAME ?= myapp
TTL ?= 30

up:
	@echo "Starting platform..."
	@docker start sandbox-nginx 2>/dev/null || docker run -d \
		--name sandbox-nginx --network host \
		-v $(PWD)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
		-v $(PWD)/nginx/conf.d:/etc/nginx/conf.d:ro \
		--restart unless-stopped nginx:latest
	@nohup $(PLATFORM)/cleanup_daemon.sh >> logs/cleanup.log 2>&1 &
	@nohup monitor/health_poller.sh >> logs/health_poller.log 2>&1 &
	@nohup python3 $(PLATFORM)/api.py >> logs/api.log 2>&1 &
	@echo "✓ Platform is up"

down:
	@echo "Stopping platform..."
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		ID=$$(python3 -c "import json; print(json.load(open('$$f'))['id'])"); \
		$(PLATFORM)/destroy_env.sh "$$ID"; \
	done
	@docker stop sandbox-nginx 2>/dev/null || true
	@pkill -f cleanup_daemon.sh 2>/dev/null || true
	@pkill -f health_poller.sh 2>/dev/null || true
	@pkill -f api.py 2>/dev/null || true
	@echo "✓ Platform is down"

create:
	@read -p "Environment name: " name; \
	read -p "TTL in minutes [30]: " ttl; \
	ttl=$${ttl:-30}; \
	$(PLATFORM)/create_env.sh "$$name" "$$ttl"

destroy:
	@[ -n "$(ENV)" ] || (echo "Usage: make destroy ENV=env-xxx"; exit 1)
	@$(PLATFORM)/destroy_env.sh "$(ENV)"

logs:
	@[ -n "$(ENV)" ] || (echo "Usage: make logs ENV=env-xxx"; exit 1)
	@tail -f logs/$(ENV)/app.log

health:
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		python3 -c "import json; d=json.load(open('$$f')); print(f\"{d['id']} | {d['name']} | {d['status']}\")"; \
	done

simulate:
	@[ -n "$(ENV)" ] || (echo "Usage: make simulate ENV=env-xxx MODE=crash"; exit 1)
	@$(PLATFORM)/simulate_outage.sh --env "$(ENV)" --mode "$(MODE)"

clean:
	@rm -rf logs/* envs/* nginx/conf.d/*.conf
	@mkdir -p logs/archived
	@echo "✓ State and logs wiped"
