## Streaming to an Icecast server

Groovebox has built-in support for streaming to Icecast-compatible servers. This example provides a super basic configuration for streaming a short playlist of pre-encoded media files to an Icecast server running locally.

## Prerequisites
- An Icecast server running locally or remotely. You can download and install Icecast from [Icecast.org](https://icecast.org/).
- Pre-encoded media files in OGG format for streaming to Icecast. You can use the built-in `ogg` command in Groovebox to convert your audio files to OGG format.


### Running the example
1. Once you have initialized your Groovebox config, you can start the Icecast server

```bash
icecast -c /opt/local/etc/icecast.xml
```

> [!NOTE]
> The path to `icecast.xml` may vary based on your installation. Make sure to adjust the path accordingly.

2. Next, run the Groovebox example to start streaming to the Icecast server:

```bash
groovebox icecast groovebox_config.yml
```

3. Open your web browser and navigate to `http://localhost:8000/stream` to listen to the stream.

> [!NOTE]
> There are plans to implement an Icecast server within Groovebox itself in the future, which will allow for fine-grained control, dashboard monitoring, membership management and more. Stay tuned!

Groovebox streams to any Icecast servers using low memory and CPU resources because it does not re-encode the media files. Instead, it streams the pre-encoded OGG files directly to the server. This means that you can use Groovebox to stream high-quality audio without worrying about performance issues.

The downside of this approach is that you need to pre-encode your media files in OGG format before streaming them with Groovebox, and you won't be able to use the usual live effects and controls that Liquidsoap provides.

However, Groovebox is designed to be a simple and efficient streaming solution for backyard radio stations, parties, coffee shops, and other small venues.

🤘 Music in this example is generated with Suno AI