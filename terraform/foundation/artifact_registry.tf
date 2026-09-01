# Named "pipeline" not "quakes" because Ex02 adds a webhook image and Ex03
# adds an SSE bridge image. One repo, several images.
resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "pipeline"
  format        = "DOCKER"
  description   = "Container images for all exercises"

  depends_on = [google_project_service.enabled]
}
