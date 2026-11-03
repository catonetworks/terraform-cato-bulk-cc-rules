# terraform-cato-bulk-cc-rules
#
# Bulk-manages the Cato Client Connectivity (clientConnectivity) policy from one JSON
# export produced by `catocli export cc_rules`:
#   sections[] / rules[] / rules_in_sections[] - flat policy, no sub-policies.
# cato_bulk_cc_move_rule applies ordering and republishes.
# Rule fields: action, confidenceLevel, connectionOrigin, country, device, platform, source{user,usersGroup}, sourceRange[].globalIpRange.

locals {
  cc_json = jsondecode(file("${var.cc_rules_json_file_path}"))
  cc      = local.cc_json.data.policy.clientConnectivity.policy

  sections_data_raw      = try(local.cc.sections, [])
  rules_data_raw         = try(local.cc.rules, [])
  rules_in_sections_data = try(local.cc.rules_in_sections, [])

  sections_data = {
    for s in local.sections_data_raw : s.section_name => s
  }

  rules_by_name = {
    for rw in local.rules_data_raw : rw.rule.name => rw
  }

  move_section_data = {
    for name, s in local.sections_data : name => {
      section_index = s.section_index
    }
  }

  move_rule_data = {
    for row in local.rules_in_sections_data :
    row.rule_name => {
      index_in_section = row.index_in_section
      section_name     = row.section_name
    }
    if row.section_name != "" && contains(keys(local.sections_data), row.section_name)
  }

  unordered_rules_data = [
    for row in local.rules_in_sections_data : row
    if !contains(keys(local.move_rule_data), try(row.rule_name, ""))
  ]

  rule_bodies = {
    for name, rw in local.rules_by_name : name => merge(
      {
        name             = rw.rule.name
        enabled          = try(rw.rule.enabled, true)
        action           = try(rw.rule.action, "ALLOW")
        confidence_level = try(rw.rule.confidenceLevel, "HIGH")
      },
      try(rw.rule.description, "") != "" ? { description = rw.rule.description } : {},
      try(length(rw.rule.connectionOrigin), 0) > 0 ? { connection_origin = rw.rule.connectionOrigin } : {},
      try(length(rw.rule.country), 0) > 0 ? { country = [for x in rw.rule.country : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
      try(length(rw.rule.device), 0) > 0 ? { device = [for x in rw.rule.device : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
      try(length(rw.rule.platform), 0) > 0 ? { platform = rw.rule.platform } : {},
      try(length(rw.rule.source.user), 0) > 0 || try(length(rw.rule.source.usersGroup), 0) > 0 ? {
        source = merge(
          try(length(rw.rule.source.user), 0) > 0 ? { user = [for x in rw.rule.source.user : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
          try(length(rw.rule.source.usersGroup), 0) > 0 ? { users_group = [for x in rw.rule.source.usersGroup : can(x.name) ? { name = x.name } : { id = x.id }] } : {}
        )
      } : {},
      try(length(rw.rule.sourceRange), 0) > 0 ? {
        source_range = [for sr in rw.rule.sourceRange : {
          global_ip_range = can(sr.globalIpRange.name) ? { name = sr.globalIpRange.name } : { id = sr.globalIpRange.id }
        }]
      } : {}
    )
  }
}

# Optional account-level policy toggle (Client Connectivity ships disabled on new
# tenants - without enabling it, published rules have no effect).
resource "cato_client_connectivity_policy" "policy" {
  count   = var.policy_enabled == null ? 0 : 1
  enabled = var.policy_enabled
}

resource "cato_client_connectivity_section" "sections" {
  for_each = local.sections_data
  at = {
    position = "LAST_IN_POLICY"
  }
  section = {
    name = each.value.section_name
  }
}

resource "cato_client_connectivity_rule" "rules" {
  depends_on = [cato_client_connectivity_section.sections]
  for_each   = local.rules_by_name

  at = contains(keys(local.sections_data), each.value.rule.section.name) ? {
    position = "LAST_IN_SECTION"
    ref      = cato_client_connectivity_section.sections[each.value.rule.section.name].id
    } : {
    position = "LAST_IN_POLICY"
  }

  rule = local.rule_bodies[each.key]
}

# Ordering + republish on changes.
resource "cato_bulk_cc_move_rule" "all_cc_rules" {
  depends_on = [cato_client_connectivity_section.sections, cato_client_connectivity_rule.rules]

  section_data = local.move_section_data
  rule_data    = local.move_rule_data
}
