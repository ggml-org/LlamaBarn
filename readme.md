# LlamaBarn

Run local LLMs on your Mac with a friendly menu bar app. Launch any model with a single click, then chat with it via the built-in web UI or use it via the REST API. LlamaBarn automatically configures models based on your Mac's hardware to ensure optimal performance and stability.

Download the latest version from [Releases ↗](https://github.com/ggml-org/LlamaBarn/releases)

![LlamaBarn](https://i.imgur.com/S2jzV6Y.png)

## Highlights

- Lightweight -- `~12 MB` or `~6 MB` zipped
- Curated model catalog
- Model configurations that adapt to device's memory and GPU
- Basic Web UI for interacting with running models
- Familiar REST API for developers

## How it works

- LlamaBarn is a thin wrapper around `llama.cpp`
- When you run a model, it launches `llama-server` on `localhost:2276`
- You can chat in the server's web UI or via the API

## API Endpoints

Check server health:

```sh
curl http://localhost:2276/v1/health
```

List running models (limited to one at a time for now):
```sh
curl http://localhost:2276/v1/models
```

Chat with the running model
```sh
curl http://localhost:2276/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hi"}]}'
```

Learn more at in the `llama-server` [docs](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints).

## Roadmap

- [ ] Support for Embedding models
- [ ] Support for Completion models
- [ ] Support for running multiple models at a time -- e.g., chat + embeddings
- [ ] Support for parallel requests 
- [ ] Vision support for vision-capable models
- [ ] Advanced settings for power users -- without complicating things for everyone else

## License and acknowledgements

Licensed under the MIT License. See `LICENSE`.

Built on top of the `llama.cpp` and `ggml` ecosystem.
