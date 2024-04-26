#!/bin/bash

BUNDLE="build/App.app/Contents"

mkdir -p "$BUNDLE/Frameworks"
mkdir -p "$BUNDLE/MacOS"
mkdir -p "$BUNDLE/Resources"
mkdir -p "$BUNDLE/_CodeSignature"

xcrun -sdk macosx metal -o ./src/shaders.ir  -c ./src/shaders.metal
xcrun -sdk macosx metallib -o "$BUNDLE/Resources/shaders.metallib" ./src/shaders.ir

clang -g -Wall -framework Cocoa -framework Metal -framework QuartzCore ./src/main.m -o "$BUNDLE/MacOS/bin"

cp ./src/Info.plist "$BUNDLE/Info.plist"
cp ./src/PkgInfo "$BUNDLE/PkgInfo"