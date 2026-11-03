variable "cc_rules_json_file_path" {
  description = "Path to the Client Connectivity JSON export produced by `catocli export cc_rules` (data.policy.clientConnectivity.policy root)."
  type        = string
}

variable "policy_enabled" {
  description = "Manage the account-level Client Connectivity policy toggle. null leaves the toggle unmanaged; true/false manages it via cato_client_connectivity_policy."
  type        = bool
  default     = null
}
