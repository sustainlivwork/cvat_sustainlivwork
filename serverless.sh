#!/usr/bin/env bash
# Convenience wrapper for the Nuclio serverless overlay — the default launch
# for this fork. Brings CVAT up with the AI-annotation subsystem enabled.
#
#   ./serverless.sh up      # start CVAT with serverless (Nuclio) active
#   ./serverless.sh down    # stop the stack
#   ./serverless.sh logs    # tail nuclio + cvat_server + annotation worker
#   ./serverless.sh ...      # any other docker-compose subcommand
#
# No AI models are deployed by this script. The serverless subsystem comes up
# empty: CVAT's semi-automatic tools appear in the UI but list no models until
# you deploy one (see README, "Semi-automatic annotation"). Deploying is done
# from the cvat_models repo; this script only picks up its compose overlay once
# that repo has staged it here.
#
# Without this script (plain CVAT, no AI subsystem):
#   docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
set -euo pipefail
cd "$(dirname "$0")"

FILES=(
  -f docker-compose.yml
  -f components/serverless/docker-compose.serverless.yml
)
# Include the dev overlay if present so this fork's branded images are built
# from source rather than pulled as stock CVAT.
[[ -f docker-compose.dev.yml ]] && FILES+=(-f docker-compose.dev.yml)
# Include the cvat_models overlay once it has been staged here (cvat_models'
# scripts/launch.sh copies it in). It bind-mounts ./serverless into the Nuclio
# dashboard so nuctl can read the staged function sources, and pins the build
# platform to amd64 on arm64 hosts. Absent until you stage a model, so plain
# serverless launches are unaffected.
[[ -f docker-compose.models.yml ]] && FILES+=(-f docker-compose.models.yml)

case "${1:-}" in
  logs)
    shift
    exec docker compose "${FILES[@]}" logs -f --tail=200 \
      nuclio cvat_server cvat_worker_annotation "$@"
    ;;
  *)
    exec docker compose "${FILES[@]}" "$@"
    ;;
esac
