# MITRE ATT&CK tag namespace and Scanner-supported sources

Read this file during Phase 4 (gap analysis) of `generate-health-report`. These are the canonical tag IDs and source slugs to cite verbatim in the report — do not guess from memory.

## Tactics (14 total)

```
tactics.ta0043.reconnaissance
tactics.ta0042.resource_development
tactics.ta0001.initial_access
tactics.ta0002.execution
tactics.ta0003.persistence
tactics.ta0004.privilege_escalation
tactics.ta0005.defense_evasion
tactics.ta0006.credential_access
tactics.ta0007.discovery
tactics.ta0008.lateral_movement
tactics.ta0009.collection
tactics.ta0011.command_and_control
tactics.ta0010.exfiltration
tactics.ta0040.impact
```

## Techniques

```
techniques.t1001.data_obfuscation
techniques.t1003.os_credential_dumping
techniques.t1005.data_from_local_system
techniques.t1006.direct_volume_access
techniques.t1007.system_service_discovery
techniques.t1008.fallback_channels
techniques.t1010.application_window_discovery
techniques.t1011.exfiltration_over_other_network_medium
techniques.t1012.query_registry
techniques.t1014.rootkit
techniques.t1016.system_network_configuration_discovery
techniques.t1018.remote_system_discovery
techniques.t1020.automated_exfiltration
techniques.t1021.remote_services
techniques.t1025.data_from_removable_media
techniques.t1027.obfuscated_files_or_information
techniques.t1029.scheduled_transfer
techniques.t1030.data_transfer_size_limits
techniques.t1033.system_owner_user_discovery
techniques.t1036.masquerading
techniques.t1037.boot_or_logon_initialization_scripts
techniques.t1039.data_from_network_shared_drive
techniques.t1040.network_sniffing
techniques.t1041.exfiltration_over_c2_channel
techniques.t1046.network_service_scanning
techniques.t1047.windows_management_instrumentation
techniques.t1048.exfiltration_over_alternative_protocol
techniques.t1049.system_network_connections_discovery
techniques.t1052.exfiltration_over_physical_medium
techniques.t1053.scheduled_task_job
techniques.t1055.process_injection
techniques.t1056.input_capture
techniques.t1057.process_discovery
techniques.t1059.command_and_scripting_interpreter
techniques.t1068.exploitation_for_privilege_escalation
techniques.t1069.permission_groups_discovery
techniques.t1070.indicator_removal_on_host
techniques.t1071.application_layer_protocol
techniques.t1072.software_deployment_tools
techniques.t1074.data_staged
techniques.t1078.valid_accounts
techniques.t1080.taint_shared_content
techniques.t1082.system_information_discovery
techniques.t1083.file_and_directory_discovery
techniques.t1087.account_discovery
techniques.t1090.proxy
techniques.t1091.replication_through_removable_media
techniques.t1092.communication_through_removable_media
techniques.t1095.non_application_layer_protocol
techniques.t1098.account_manipulation
techniques.t1102.web_service
techniques.t1104.multi_stage_channels
techniques.t1105.ingress_tool_transfer
techniques.t1106.native_api
techniques.t1110.brute_force
techniques.t1111.two_factor_authentication_interception
techniques.t1112.modify_registry
techniques.t1113.screen_capture
techniques.t1114.email_collection
techniques.t1115.clipboard_data
techniques.t1119.automated_collection
techniques.t1120.peripheral_device_discovery
techniques.t1123.audio_capture
techniques.t1124.system_time_discovery
techniques.t1125.video_capture
techniques.t1127.trusted_developer_utilities_proxy_execution
techniques.t1129.shared_modules
techniques.t1132.data_encoding
techniques.t1133.external_remote_services
techniques.t1134.access_token_manipulation
techniques.t1135.network_share_discovery
techniques.t1136.create_account
techniques.t1137.office_application_startup
techniques.t1140.deobfuscate_decode_files_or_information
techniques.t1176.browser_extensions
techniques.t1185.browser_session_hijacking
techniques.t1187.forced_authentication
techniques.t1189.drive_by_compromise
techniques.t1190.exploit_public_facing_application
techniques.t1195.supply_chain_compromise
techniques.t1197.bits_jobs
techniques.t1199.trusted_relationship
techniques.t1200.hardware_additions
techniques.t1201.password_policy_discovery
techniques.t1202.indirect_command_execution
techniques.t1203.exploitation_for_client_execution
techniques.t1204.user_execution
techniques.t1205.traffic_signaling
techniques.t1207.rogue_domain_controller
techniques.t1210.exploitation_of_remote_services
techniques.t1211.exploitation_for_defense_evasion
techniques.t1212.exploitation_for_credential_access
techniques.t1213.data_from_information_repositories
techniques.t1216.signed_script_proxy_execution
techniques.t1217.browser_bookmark_discovery
techniques.t1218.signed_binary_proxy_execution
techniques.t1219.remote_access_software
techniques.t1220.xsl_script_processing
techniques.t1221.template_injection
techniques.t1222.file_and_directory_permissions_modification
techniques.t1480.execution_guardrails
techniques.t1482.domain_trust_discovery
techniques.t1484.domain_policy_modification
techniques.t1485.data_destruction
techniques.t1486.data_encrypted_for_impact
techniques.t1489.service_stop
techniques.t1490.inhibit_system_recovery
techniques.t1491.defacement
techniques.t1495.firmware_corruption
techniques.t1496.resource_hijacking
techniques.t1497.virtualization_sandbox_evasion
techniques.t1498.network_denial_of_service
techniques.t1499.endpoint_denial_of_service
techniques.t1505.server_software_component
techniques.t1518.software_discovery
techniques.t1525.implant_internal_image
techniques.t1526.cloud_service_discovery
techniques.t1528.steal_application_access_token
techniques.t1529.system_shutdown_reboot
techniques.t1530.data_from_cloud_storage_object
techniques.t1531.account_access_removal
techniques.t1534.internal_spearphishing
techniques.t1535.unused_unsupported_cloud_regions
techniques.t1537.transfer_data_to_cloud_account
techniques.t1538.cloud_service_dashboard
techniques.t1539.steal_web_session_cookie
techniques.t1542.pre_os_boot
techniques.t1543.create_or_modify_system_process
techniques.t1546.event_triggered_execution
techniques.t1547.boot_or_logon_autostart_execution
techniques.t1548.abuse_elevation_control_mechanism
techniques.t1550.use_alternate_authentication_material
techniques.t1552.unsecured_credentials
techniques.t1553.subvert_trust_controls
techniques.t1554.compromise_client_software_binary
techniques.t1555.credentials_from_password_stores
techniques.t1556.modify_authentication_process
techniques.t1557.adversary_in_the_middle
techniques.t1558.steal_or_forge_kerberos_tickets
techniques.t1559.inter_process_communication
techniques.t1560.archive_collected_data
techniques.t1561.disk_wipe
techniques.t1562.impair_defenses
techniques.t1563.remote_service_session_hijacking
techniques.t1564.hide_artifacts
techniques.t1565.data_manipulation
techniques.t1566.phishing
techniques.t1567.exfiltration_over_web_service
techniques.t1568.dynamic_resolution
techniques.t1569.system_services
techniques.t1570.lateral_tool_transfer
techniques.t1571.non_standard_port
techniques.t1572.protocol_tunneling
techniques.t1573.encrypted_channel
techniques.t1574.hijack_execution_flow
techniques.t1578.modify_cloud_compute_infrastructure
techniques.t1580.cloud_infrastructure_discovery
techniques.t1583.acquire_infrastructure
techniques.t1584.compromise_infrastructure
techniques.t1585.establish_accounts
techniques.t1586.compromise_accounts
techniques.t1587.develop_capabilities
techniques.t1588.obtain_capabilities
techniques.t1589.gather_victim_identity_information
techniques.t1590.gather_victim_network_information
techniques.t1591.gather_victim_org_information
techniques.t1592.gather_victim_host_information
techniques.t1593.search_open_websites_domains
techniques.t1594.search_victim_owned_websites
techniques.t1595.active_scanning
techniques.t1596.search_open_technical_databases
techniques.t1597.search_closed_sources
techniques.t1598.phishing_for_information
techniques.t1599.network_boundary_bridging
techniques.t1600.weaken_encryption
techniques.t1601.modify_system_image
techniques.t1602.data_from_configuration_repository
techniques.t1606.forge_web_credentials
techniques.t1608.stage_capabilities
techniques.t1609.container_administration_command
techniques.t1610.deploy_container
techniques.t1611.escape_to_host
techniques.t1612.build_image_on_host
techniques.t1613.container_and_resource_discovery
techniques.t1614.system_location_discovery
techniques.t1615.group_policy_discovery
techniques.t1619.cloud_storage_object_discovery
techniques.t1620.reflective_code_loading
```

## Scanner-supported log sources (canonical slugs)

Use these exact slugs in recommendations.

- **AWS:** `aws-cloudtrail`, `aws-cloudwatch`, `aws-vpc-flow`, `aws-vpc-transit-gateway-flow`, `aws-route53-resolver`, `aws-guardduty`, `aws-waf`, `aws-aurora`, `aws-lambda`, `aws-ecs`, `aws-eks`
- **Other cloud:** `azure-activity`, `google-cloud-platform-gcp-audit`
- **Identity / SSO:** `okta`, `auth0`, `1password`, `google-workspace`
- **Endpoint / EDR:** `crowdstrike`, `sentinelone`, `sophos`, `windows-defender`, `windows-sysmon`, `jamf`, `osquery`, `ossec`
- **Network:** `cloudflare`, `fastly`, `zeek`, `suricata`
- **SaaS / Collaboration:** `github`, `slack`
- **Data platforms:** `snowflake`
- **Cloud security / CSPM:** `wiz`, `lacework`
- **Email security:** `sublime-security`
- **Access / ZTNA:** `teleport`
- **Generic ingestion:** `custom-logs-aws-s3`, `custom-logs-http`, `custom-via-fluentd`, `syslog`

## Sources bridgeable via Monad

If the customer uses Monad (monad.com) as a data pipeline, these can be routed into Scanner. Recommend only when Scanner has no native integration and the source meaningfully expands coverage.

- **Identity / IAM:** OneLogin, JumpCloud, Duo Security
- **Dev / CI / Supply chain:** GitLab, Buildkite, Vercel, Semgrep, Snyk, Socket.dev, Cloudsmith, Akuity
- **Vuln mgmt / threat feeds:** Tenable, Prowler, Veracode, Endor Labs, Brinqa, CISA KEV
- **SaaS / Collaboration:** Atlassian (Jira, Confluence), Salesforce, ServiceNow, Zendesk, Zoom, DocuSign, PagerDuty, Figma, Coda, Postman, Glean, Greenhouse, Twilio, Workato, Workiva, Rootly, Captivate IQ, Opal
- **Monitoring / APM:** Sentry, Bugsnag, Tanium, Fleet, Arize
- **Backup / storage:** Backblaze, Box, Ownbackup, Clumio
- **Secrets / DLP:** Bitwarden, Nightfall, Polymer, Kolide
- **Network / SASE:** Cato Networks, Cisco Meraki, Tailscale
- **AI APIs:** OpenAI, Anthropic
- **Other platforms:** MongoDB, Aiven, Persona, Koi
- **Generic:** Monad's generic input
