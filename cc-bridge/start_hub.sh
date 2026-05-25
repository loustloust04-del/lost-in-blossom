#!/bin/bash
set -e
cd "$(dirname "$0")"
exec bun run hub.ts
