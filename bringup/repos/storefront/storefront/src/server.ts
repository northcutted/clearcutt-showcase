// storefront: the showcase's web front end, a small Fastify service.
import Fastify from "fastify";

const app = Fastify({ logger: true });

const greeting = "Welcome to the ClearCutt tea shop";

app.get("/healthz", async () => ({ status: "ok", service: "storefront", node: process.version }));

app.get("/", async () => ({
  greeting,
  links: { products: "/api/products", checkout: "/api/checkout" },
}));

const port = Number(process.env.PORT ?? 8080);

try {
  await app.listen({ host: "0.0.0.0", port });
} catch (err) {
  app.log.error(err);
  process.exit(1);
}

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    void app.close().then(() => process.exit(0));
  });
}
