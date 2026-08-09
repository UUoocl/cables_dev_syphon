#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Starting build and installation of the custom Cables local dev environment...${NC}"

# Step 1: Check and install missing prebuilt dependencies (Syphon.framework)
if [ ! -d "reference/syphon-server-plugin/.deps/obs-deps-2025-08-23-universal/lib/Syphon.framework" ]; then
    echo -e "${RED}OBS dependencies containing Syphon.framework are missing. Downloading...${NC}"
    mkdir -p reference/syphon-server-plugin/.deps/obs-deps-2025-08-23-universal
    curl -L -o reference/obs-deps.tar.xz https://github.com/obsproject/obs-deps/releases/download/2025-08-23/macos-deps-2025-08-23-universal.tar.xz
    tar -xJf reference/obs-deps.tar.xz -C reference/syphon-server-plugin/.deps/obs-deps-2025-08-23-universal
    rm reference/obs-deps.tar.xz
    echo -e "${GREEN}OBS dependencies downloaded and extracted successfully.${NC}"
fi

# Step 2: Install cables_dev root dependencies
echo -e "${GREEN}Installing root cables_dev dependencies...${NC}"
cd cables_dev
npm install

# Step 3: Install and build shared package
echo -e "${GREEN}Installing and building shared package...${NC}"
cd shared
npm install
npm run build
cd ..

# Step 4: Install and build cables core package
echo -e "${GREEN}Installing and building cables core package...${NC}"
cd cables
npm install
npm run build
cd ..

# Step 5: Install and build cables_ui package (includes building fonts)
echo -e "${GREEN}Installing and building cables_ui package...${NC}"
cd cables_ui
npm install
npm run build
# Deploy MSDF editor canvas font texture
mkdir -p dist/img
if [ -f "../../cables_ui/cables_ui/dist/img/worksans-regular.png" ]; then
    cp ../../cables_ui/cables_ui/dist/img/worksans-regular.png dist/img/worksans-regular.png
elif [ -f "../cables_ui/dist/img/worksans-regular.png" ]; then
    cp ../cables_ui/dist/img/worksans-regular.png dist/img/worksans-regular.png
else
    cp ../cables_electron/resources/assets/library/fonts_msdf/WorkSans-Regular.ttf.png dist/img/worksans-regular.png
fi
cd ..

# Step 6: Install and build cables_electron package
echo -e "${GREEN}Installing and building cables_electron package...${NC}"
cd cables_electron
npm install
npm run build
cd ..

# Step 7: Compile native Apple Frameworks addon
echo -e "${GREEN}Installing and compiling cables_apple_frameworks...${NC}"
cd ../cables_apple_frameworks
npm install
npm run install

cd ..

echo -e "${GREEN}Local development environment setup completed successfully!${NC}"
echo -e "To start the development server, run:"
echo -e "  ${GREEN}cd cables_dev/cables_electron && npm run start${NC}"
