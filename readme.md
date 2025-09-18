# LlamaBarn 🦙 🌾

Run local LLMs on your Mac with a simple menu bar app. Launch any model with a single click, then chat with it via the built-in web UI or connect to it via the REST API. LlamaBarn automatically configures models based on your Mac's hardware to ensure optimal performance and stability.

Download the latest version from [Releases ↗](https://github.com/ggml-org/LlamaBarn/releases).

<br>

![LlamaBarn](https://i.imgur.com/S2jzV6Y.png)

<br>

## Highlights

- **Simple.** Just a thin (`12 MB`) wrapper around `llama.cpp` for minimal resource usage and instant startup.
- **Native.** Built with macOS technologies and UI patterns for seamless integration and familiar interactions.
- **Hardware-aware.** Suggests models and uses configurations based on your Mac's hardware.
- **Easy to use.** Run, manage, and monitor models directly from your macOS menu bar -- no setup or technical steps required.
- **Easy to develop for.** Connect your own applications via a familiar REST API.
- **Free and open source.** Licensed under the `MIT License`.

<br>

## Goals

<!-- how things shd be -->

- **Make it easy for everyone to use local LLMs.** Using local LLMs should not require technical knowldege. You should be able to just select a model from a list and start using it. Technical customizations should be possible, but not required.
- **Make it easy for developers to add support for local LLMs to their apps.** Adding support for local LLMs should be just as easy as adding support for cloud-based LLMs. You shouldn't have to implement custom UIs for managing models, starting servers, etc.

<br>

## How it works

LlamaBarn is a thin wrapper around `llama.cpp` -- it manages the `llama.cpp` server (`llama-server`) for you, handling all the complex configuration so you don't have to.

Here’s what happens under the hood:

- **You select a model** from our curated catalog.
- **We configure it** automatically based on your Mac's specific hardware (RAM, GPU, etc.).
- **We start a local server** at `http://localhost:2276`.

Once the server is running, you have two ways to interact with your model:

- **Chat instantly** -- open the address in your browser to use the built-in web UI.
- **Integrate with apps** -- connect any application to the standard REST API endpoints.

In short, we provide the simplicity of a one-click menu bar app, and you get the full power of a locally hosted `llama.cpp` server.

<br>

## API endpoints

LlamaBarn uses the `llama.cpp` server (`llama-server`) and therefore supports the same API endpoints including:

```sh
# check server health
curl http://localhost:2276/v1/health
```

```sh
# list running models (limited to one at a time for now)
curl http://localhost:2276/v1/models
```

```sh
# chat with the running model
curl http://localhost:2276/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hi"}]}'
```

Find the full documentation for the API endpoints in the `llama.cpp` [docs](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints).

<br>

## Roadmap

- [ ] Support for embedding models
- [ ] Support for completion models
- [ ] Support for running multiple models at a time -- e.g., chat + embeddings
- [ ] Support for parallel requests
- [ ] Support for vision in vision-capable models
- [ ] Advanced settings for power users -- without complicating things for everyone else

<br>

## License

Licensed under the MIT License. See `LICENSE`.
