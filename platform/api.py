import subprocess, json, os, glob
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Optional
import time

app = FastAPI(title="DevOps Sandbox API")

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLATFORM_DIR = os.path.join(ROOT_DIR, "platform")

def get_state(env_id: str):
    path = os.path.join(ROOT_DIR, "envs", f"{env_id}.json")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail=f"Environment {env_id} not found")
    with open(path) as f:
        return json.load(f)

class CreateEnvRequest(BaseModel):
    name: str
    ttl: Optional[int] = 30

class OutageRequest(BaseModel):
    mode: str

# POST /envs — create environment
@app.post("/envs")
def create_env(req: CreateEnvRequest):
    result = subprocess.run(
        [os.path.join(PLATFORM_DIR, "create_env.sh"), req.name, str(req.ttl)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise HTTPException(status_code=500, detail=result.stderr)
    env_files = glob.glob(os.path.join(ROOT_DIR, "envs", "*.json"))
    latest = max(env_files, key=os.path.getctime)
    with open(latest) as f:
        return json.load(f)

# GET /envs — list all active environments
@app.get("/envs")
def list_envs():
    envs = []
    now = time.time()
    for path in glob.glob(os.path.join(ROOT_DIR, "envs", "*.json")):
        with open(path) as f:
            state = json.load(f)
        expires_at = state["created_at"] + state["ttl"]
        state["ttl_remaining_seconds"] = max(0, int(expires_at - now))
        envs.append(state)
    return envs

# DELETE /envs/:id — destroy environment
@app.delete("/envs/{env_id}")
def destroy_env(env_id: str):
    get_state(env_id)
    result = subprocess.run(
        [os.path.join(PLATFORM_DIR, "destroy_env.sh"), env_id],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise HTTPException(status_code=500, detail=result.stderr)
    return {"message": f"Environment {env_id} destroyed"}

# GET /envs/:id/logs — last 100 lines
@app.get("/envs/{env_id}/logs")
def get_logs(env_id: str):
    get_state(env_id)
    log_paths = [
        os.path.join(ROOT_DIR, "logs", env_id, "app.log"),
        os.path.join(ROOT_DIR, "logs", "archived", env_id, "app.log")
    ]
    for path in log_paths:
        if os.path.exists(path):
            result = subprocess.run(["tail", "-n", "100", path], capture_output=True, text=True)
            return {"env_id": env_id, "logs": result.stdout.splitlines()}
    return {"env_id": env_id, "logs": []}

# GET /envs/:id/health — last 10 health results
@app.get("/envs/{env_id}/health")
def get_health(env_id: str):
    state = get_state(env_id)
    health_log = os.path.join(ROOT_DIR, "logs", env_id, "health.log")
    lines = []
    if os.path.exists(health_log):
        result = subprocess.run(["tail", "-n", "10", health_log], capture_output=True, text=True)
        lines = result.stdout.splitlines()
    return {"env_id": env_id, "status": state["status"], "health_checks": lines}

# POST /envs/:id/outage — trigger simulation
@app.post("/envs/{env_id}/outage")
def trigger_outage(env_id: str, req: OutageRequest):
    get_state(env_id)
    result = subprocess.run(
        [os.path.join(PLATFORM_DIR, "simulate_outage.sh"), "--env", env_id, "--mode", req.mode],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise HTTPException(status_code=500, detail=result.stderr)
    return {"env_id": env_id, "mode": req.mode, "result": result.stdout}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
