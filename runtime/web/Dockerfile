FROM ghcr.io/ever-co/gauzy-webapp:latest
WORKDIR /srv/gauzy
COPY brand/ ./assets/branding/dshinez/
COPY onboarding.html ./assets/branding/dshinez/onboarding.html
COPY onboarding.js ./assets/branding/dshinez/onboarding.js
COPY manifest.json ./manifest.json
RUN grep -q '<body>' index.html && grep -q '</head>' index.html \
    && sed -i 's|<body>|<body class="dshinez-app">|; s|<title>[^<]*</title>|<title>D’Shinez Holdings</title>|; s|</head>|<link rel="stylesheet" href="/assets/branding/dshinez/theme.css"></head>|' index.html \
    && grep -q '<title>D’Shinez Holdings</title>' index.html \
    && mkdir -p assets/images/logos \
    && cp assets/branding/dshinez/wordmark.png assets/images/logos/logo_Gauzy.png \
    && cp assets/branding/dshinez/app-icon.png favicon.png \
    && sed -i 's|href="favicon.ico"|href="favicon.png"|; s|type="image/x-icon"|type="image/png"|' index.html
