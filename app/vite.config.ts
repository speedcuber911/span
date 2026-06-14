import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";
import path from "path";

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      injectRegister: false, // we register manually in main.tsx for reload control
      includeAssets: [
        "favicon.svg",
        "favicon-48.png",
        "apple-touch-icon.png",
        "health_data.json",
      ],
      manifest: {
        name: "Health Trends Explorer",
        short_name: "Health Trends",
        description: "Anoop's diagnostic lab history — trends, panels & alerts.",
        theme_color: "#0f172a",
        background_color: "#0f172a",
        display: "standalone",
        orientation: "portrait",
        scope: "/",
        start_url: "/",
        icons: [
          { src: "icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "icon-512.png", sizes: "512x512", type: "image/png" },
          { src: "icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
      workbox: {
        // cache app shell + the large data file so it works fully offline
        globPatterns: ["**/*.{js,css,html,svg,png,json}"],
        maximumFileSizeToCacheInBytes: 5 * 1024 * 1024,
        // promptly retire stale caches + take control so updates apply on reload
        cleanupOutdatedCaches: true,
        skipWaiting: true,
        clientsClaim: true,
        // always revalidate the HTML entry so a new build is picked up fast
        navigateFallback: "index.html",
        runtimeCaching: [
          {
            urlPattern: ({ url }) => url.pathname.endsWith("health_data.json"),
            handler: "StaleWhileRevalidate",
            options: {
              cacheName: "health-data",
              expiration: { maxEntries: 2 },
            },
          },
        ],
      },
    }),
  ],
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
