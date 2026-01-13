import os

import uvicorn


def main() -> None:
    host = os.environ.get("HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "9001"))
    uvicorn.run("embedding_worker.main:app", host=host, port=port, reload=True)


if __name__ == "__main__":
    main()

