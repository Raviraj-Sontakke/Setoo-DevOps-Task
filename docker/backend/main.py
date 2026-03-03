import os
from contextlib import asynccontextmanager
from typing import Optional

import databases
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/tasks"
)

database = databases.Database(DATABASE_URL)

CREATE_TABLE = """
CREATE TABLE IF NOT EXISTS tasks (
    id         SERIAL PRIMARY KEY,
    title      VARCHAR(255) NOT NULL,
    completed  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
)
"""


@asynccontextmanager
async def lifespan(app: FastAPI):
    await database.connect()
    await database.execute(CREATE_TABLE)
    yield
    await database.disconnect()


app = FastAPI(title="Tasks API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class TaskCreate(BaseModel):
    title: str


class TaskPatch(BaseModel):
    completed: Optional[bool] = None
    title: Optional[str] = None


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/tasks")
async def list_tasks():
    rows = await database.fetch_all("SELECT * FROM tasks ORDER BY created_at DESC")
    return [dict(r) for r in rows]


@app.post("/tasks", status_code=201)
async def create_task(body: TaskCreate):
    row_id = await database.execute(
        "INSERT INTO tasks (title) VALUES (:title) RETURNING id",
        {"title": body.title},
    )
    row = await database.fetch_one("SELECT * FROM tasks WHERE id = :id", {"id": row_id})
    return dict(row)


@app.patch("/tasks/{task_id}")
async def update_task(task_id: int, body: TaskPatch):
    existing = await database.fetch_one(
        "SELECT * FROM tasks WHERE id = :id", {"id": task_id}
    )
    if not existing:
        raise HTTPException(status_code=404, detail="Task not found")

    updates = {}
    if body.completed is not None:
        updates["completed"] = body.completed
    if body.title is not None:
        updates["title"] = body.title

    if updates:
        set_clause = ", ".join(f"{k} = :{k}" for k in updates)
        updates["id"] = task_id
        await database.execute(f"UPDATE tasks SET {set_clause} WHERE id = :id", updates)

    row = await database.fetch_one("SELECT * FROM tasks WHERE id = :id", {"id": task_id})
    return dict(row)


@app.delete("/tasks/{task_id}", status_code=204)
async def delete_task(task_id: int):
    existing = await database.fetch_one(
        "SELECT * FROM tasks WHERE id = :id", {"id": task_id}
    )
    if not existing:
        raise HTTPException(status_code=404, detail="Task not found")
    await database.execute("DELETE FROM tasks WHERE id = :id", {"id": task_id})
