module.exports = {
    apps: [
        {
            name: "uptime-kuma",
            script: "./server/server.js",
            env: {
                UPTIME_KUMA_HOST: "0.0.0.0",
                UPTIME_KUMA_TRUST_PROXY: "1"
            }
        },
    ],
};
