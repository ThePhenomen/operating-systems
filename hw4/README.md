### Nginx + web-servers

To start applications run the followning command:
```bash
docker-compose up -d --build
```

Add the following line to /etc/hosts:
```
127.0.0.1 hello-world-app.dmatushkin.hw my-app.dmatushkin.hw
```

Run the following commands to interact with the web-servers:

```bash
curl http://hello-world-app.dmatushkin.hw
curl http://my-app.dmatushkin.hw
curl -X POST http://my-app.dmatushkin.hw/create
```

