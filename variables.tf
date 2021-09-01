variable "project" {
  type        = string
  description = "Google Cloud project ID."
}

variable "zone" {
  type        = string
  description = "Google Cloud zone."

  validation {
    condition     = contains([
      "us-west1-a",
      "us-west1-b",
      "us-west1-c",
      "us-central1-a",
      "us-central1-b",
      "us-central1-c",
      "us-central1-f",
      "us-east1-b",
      "us-east1-c",
      "us-east1-d"
    ], var.zone)
    error_message = "Invalid GCP free tier zone."
  }
}

variable "instance_name" {
  type        = string
  description = "Compute Engine VM instance name."
}

variable "ipsec_identifier" {
  type        = string
  description = "IPSec identifier."
}

variable "hostname" {
  type        = string
  description = "Hostname."
}

variable "dyndns" {
  type        = object({
    server   = string
    user     = string
    password = string
  })
  description = "Dynamic DNS parameters."
  sensitive   = true
}