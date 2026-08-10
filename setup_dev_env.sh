#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Starting build and installation of the custom Cables local dev environment...${NC}"

# Step 1: Verify bundled dependencies (Syphon.framework)
if [ ! -d "cables_apple_frameworks/frameworks/Syphon.framework" ]; then
    echo -e "${RED}Error: Syphon.framework missing from cables_apple_frameworks/frameworks/${NC}"
    exit 1
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
echo -e "${GREEN}Syncing Apple Framework ops...${NC}"
./sync_apple_framework_ops.sh

echo -e "${GREEN}Installing and building cables core package...${NC}"
cd cables
npm install
npm run build
cd ..

# Step 5: Install and build cables_ui package (includes building fonts)
echo -e "${GREEN}Installing and building cables_ui package...${NC}"
cd cables_ui
cp ../cables_electron/resources/assets/library/fonts_msdf/WorkSans-Regular.ttf.font.json src/ui/glpatch/sdf_font.json
npm install
npm run build
# Deploy MSDF editor canvas font texture
mkdir -p dist/img
cp ../cables_electron/resources/assets/library/fonts_msdf/WorkSans-Regular.ttf.png dist/img/worksans-regular.png
cd ..

# Step 6: Compile native Apple Frameworks addon
echo -e "${GREEN}Installing and compiling cables_apple_frameworks...${NC}"
cd ../cables_apple_frameworks
npm install
npm run install
cd ../cables_dev

# Step 7: Install and build cables_electron package
echo -e "${GREEN}Installing and building cables_electron package...${NC}"
cd cables_electron
npm install
npm run build
cd ../..

echo -e "${GREEN}Local development environment setup completed successfully!${NC}"
echo -e "To start the development server, run:"
echo -e "  ${GREEN}cd cables_dev/cables_electron && npm run start${NC}"
