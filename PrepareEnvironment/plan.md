@concat(
  '<div style="font-family:Arial, sans-serif; font-size:14px; line-height:1.6;">',
  '<p style="font-style:italic; color:#666;">This notification is sent as part of Fabric Workspace Monitoring. <a href="https://myhub.ubs.net/myhub/assist/articles/420960">Learn more</a></p>',
  '<p>Dear Workspace Owner,</p>',
  '<p>Fabric Workspace Monitoring detected following artifacts and is in process of deletion, as they were not allowed in your workspace <strong>', item().WorkspaceId, '</strong>. As mentioned in <a href="https://myhub.ubs.net/myhub/assist/articles/420960">article link</a>.</p>',
  '<table border="1" style="border-collapse:collapse; font-family:Arial; width:100%; margin:20px 0;">',
  '<thead><tr style="background-color:#E60000; color:white; font-weight:bold;">',
  '<th style="padding:8px;">Workspace ID</th>',
  '<th style="padding:8px;">Item ID</th>',
  '<th style="padding:8px;">Item Type</th>',
  '<th style="padding:8px;">Creator ID</th>',
  '<th style="padding:8px;">Created At</th>',
  '</tr></thead><tbody>',
  item().HtmlRows,
  '</tbody></table>',
  '<p>To learn more about Fabric, visit <a href="https://goto/powerhub">goto/powerhub</a>.</p>',
  '<p>For more information about constraints and limitations, visit <a href="https://ubscloud.sharepoint.com/teams/powerhub/SitePages/Power-Apps-Automate-Constraints.aspx?isSPOFile=1&xsdata=MDV8MDJ8fGQ0ZGMzMTFhNGY1NDQ5N2E1MDA0MDhkZTk2NDliOWU5fGZiNmVhNDAzN2NmMTQ5MDU4MTBhZmU1NTQ3ZTk4MjA0fDB8MHw2MzkxMTM0NDA1MjkwNDY0NzN8VW5rbm93bnxWR1ZoYlhOVFpXTjFjbWwwZVZObGNuWnBZMlY4ZXlKRFFTSTZJbFJsWVcxelgwRlVVRk5sY25acFkyVmZVMUJQVEU5R0lpd2lWaUk2SWpBdU1DNHdNREF3SWl3aVVDSTZJbGRwYmpNeUlpd2lRVTRpT2lKUGRHaGxjaUlzSWxkVUlqb3hNWDA9fDF8TDJOb1lYUnpMekU1T20xbFpYUnBibWRmVFZkT2ExcHFTVEphVkVWMFRXMVZNMWxUTURCTmFrNXJURlJyTkZwSFVYUlBSRVUwVG0xVk5FMXFTVEZPVkZKb1FIUm9jbVZoWkM1Mk1pOXRaWE56WVdkbGN5OHhOemMxTnpRM01qVXhOVEE1fDFmM2NlYzdkZWRhNjRiNjBjOTEzMDhkZTk2NDliOWU4fGU0MWY2MGNlNGM0YzRkZjY4NTEwZjk4ZjA1OTVkZjg0&sdata=ZnVHQm01Y0tZSkwrTGtwZDZ1Zlc0SEVsNmFLZ2FMS2dLUldwOXNjNUhBZz0%3D&ovuser=72f988bf-86f1-41af-91ab-2d7cd011db47%2Cabaubinas%40microsoft.com">Power Platform constraints</a> or <a href="https://ubscloud.sharepoint.com/teams/powerhub/SitePages/Power-BI-Constraints.aspx?isSPOFile=1&xsdata=MDV8MDJ8fGQ0ZGMzMTFhNGY1NDQ5N2E1MDA0MDhkZTk2NDliOWU5fGZiNmVhNDAzN2NmMTQ5MDU4MTBhZmU1NTQ3ZTk4MjA0fDB8MHw2MzkxMTM0NDA1MjkwNjcyNzl8VW5rbm93bnxWR1ZoYlhOVFpXTjFjbWwwZVZObGNuWnBZMlY4ZXlKRFFTSTZJbFJsWVcxelgwRlVVRk5sY25acFkyVmZVMUJQVEU5R0lpd2lWaUk2SWpBdU1DNHdNREF3SWl3aVVDSTZJbGRwYmpNeUlpd2lRVTRpT2lKUGRHaGxjaUlzSWxkVUlqb3hNWDA9fDF8TDJOb1lYUnpMekU1T20xbFpYUnBibWRmVFZkT2ExcHFTVEphVkVWMFRXMVZNMWxUTURCTmFrNXJURlJyTkZwSFVYUlBSRVUwVG0xVk5FMXFTVEZPVkZKb1FIUm9jbVZoWkM1Mk1pOXRaWE56WVdkbGN5OHhOemMxTnpRM01qVXhOVEE1fDFmM2NlYzdkZWRhNjRiNjBjOTEzMDhkZTk2NDliOWU4fGU0MWY2MGNlNGM0YzRkZjY4NTEwZjk4ZjA1OTVkZjg0&sdata=Z1ZTcFRzajU0Z01yNkZBcmVyejdFTkpKb1Z4V0lUTCtFYXBOcURudFNmMD0%3D&ovuser=72f988bf-86f1-41af-91ab-2d7cd011db47%2Cabaubinas%40microsoft.com">Power BI constraints</a>.</p>',
  '<p><strong>Best regards,</strong><br>',
  'UBS BizApps Team<br>',
  'Group Functions</p>',
  '<hr style="border:none; border-top:1px solid #ccc; margin:20px 0;">',
  '<p style="font-size:12px; color:#999;">',
  'Please do not reply to this automatically generated email as the mailbox is not monitored.<br>',
  '© UBS ', utcNow('yyyy'), '. For internal use only.',
  '</p>',
  '</div>'
)


















@concat(
  '<div style="font-family:Arial, sans-serif; font-size:14px; line-height:1.6;">',
  '<p style="font-style:italic; color:#666;">This notification is sent as part of Fabric Workspace Monitoring. <a href="https://myhub.ubs.net/myhub/assist/articles/420960">Learn more</a></p>',
  '<p>Dear Workspace Owner,</p>',
  '<p>Fabric Workspace Monitoring detected Outbound Access Protection change in your WorkspaceId <strong>', item().WorkspaceId, '</strong> , which is not allowed as mentioned in <a href="https://myhub.ubs.net/myhub/assist/articles/420960">article link</a>.</p>',
  '<table border="1" style="border-collapse:collapse; font-family:Arial; width:100%; margin:20px 0;">',
  '<thead><tr style="background-color:#E60000; color:white; font-weight:bold;">',
  '<th style="padding:8px;">Workspace ID</th>',
  '<th style="padding:8px;">Baseline OAP Setting</th>',
  '<th style="padding:8px;">Detected Change</th>',
  '<th style="padding:8px;">Creator ID</th>',
  '<th style="padding:8px;">Created At</th>',
  '</tr></thead><tbody>',
  item().HtmlRows,
  '</tbody></table>',
  '<p>To learn more about Fabric, visit <a href="https://goto/powerhub">goto/powerhub</a>.</p>',
  '<p>For more information about constraints and limitations, visit <a href="https://ubscloud.sharepoint.com/teams/powerhub/SitePages/Power-Apps-Automate-Constraints.aspx?isSPOFile=1&xsdata=MDV8MDJ8fGQ0ZGMzMTFhNGY1NDQ5N2E1MDA0MDhkZTk2NDliOWU5fGZiNmVhNDAzN2NmMTQ5MDU4MTBhZmU1NTQ3ZTk4MjA0fDB8MHw2MzkxMTM0NDA1MjkwNDY0NzN8VW5rbm93bnxWR1ZoYlhOVFpXTjFjbWwwZVZObGNuWnBZMlY4ZXlKRFFTSTZJbFJsWVcxelgwRlVVRk5sY25acFkyVmZVMUJQVEU5R0lpd2lWaUk2SWpBdU1DNHdNREF3SWl3aVVDSTZJbGRwYmpNeUlpd2lRVTRpT2lKUGRHaGxjaUlzSWxkVUlqb3hNWDA9fDF8TDJOb1lYUnpMekU1T20xbFpYUnBibWRmVFZkT2ExcHFTVEphVkVWMFRXMVZNMWxUTURCTmFrNXJURlJyTkZwSFVYUlBSRVUwVG0xVk5FMXFTVEZPVkZKb1FIUm9jbVZoWkM1Mk1pOXRaWE56WVdkbGN5OHhOemMxTnpRM01qVXhOVEE1fDFmM2NlYzdkZWRhNjRiNjBjOTEzMDhkZTk2NDliOWU4fGU0MWY2MGNlNGM0YzRkZjY4NTEwZjk4ZjA1OTVkZjg0&sdata=ZnVHQm01Y0tZSkwrTGtwZDZ1Zlc0SEVsNmFLZ2FMS2dLUldwOXNjNUhBZz0%3D&ovuser=72f988bf-86f1-41af-91ab-2d7cd011db47%2Cabaubinas%40microsoft.com">Power Platform constraints</a> or <a href="https://ubscloud.sharepoint.com/teams/powerhub/SitePages/Power-BI-Constraints.aspx?isSPOFile=1&xsdata=MDV8MDJ8fGQ0ZGMzMTFhNGY1NDQ5N2E1MDA0MDhkZTk2NDliOWU5fGZiNmVhNDAzN2NmMTQ5MDU4MTBhZmU1NTQ3ZTk4MjA0fDB8MHw2MzkxMTM0NDA1MjkwNjcyNzl8VW5rbm93bnxWR1ZoYlhOVFpXTjFjbWwwZVZObGNuWnBZMlY4ZXlKRFFTSTZJbFJsWVcxelgwRlVVRk5sY25acFkyVmZVMUJQVEU5R0lpd2lWaUk2SWpBdU1DNHdNREF3SWl3aVVDSTZJbGRwYmpNeUlpd2lRVTRpT2lKUGRHaGxjaUlzSWxkVUlqb3hNWDA9fDF8TDJOb1lYUnpMekU1T20xbFpYUnBibWRmVFZkT2ExcHFTVEphVkVWMFRXMVZNMWxUTURCTmFrNXJURlJyTkZwSFVYUlBSRVUwVG0xVk5FMXFTVEZPVkZKb1FIUm9jbVZoWkM1Mk1pOXRaWE56WVdkbGN5OHhOemMxTnpRM01qVXhOVEE1fDFmM2NlYzdkZWRhNjRiNjBjOTEzMDhkZTk2NDliOWU4fGU0MWY2MGNlNGM0YzRkZjY4NTEwZjk4ZjA1OTVkZjg0&sdata=Z1ZTcFRzajU0Z01yNkZBcmVyejdFTkpKb1Z4V0lUTCtFYXBOcURudFNmMD0%3D&ovuser=72f988bf-86f1-41af-91ab-2d7cd011db47%2Cabaubinas%40microsoft.com">Power BI constraints</a>.</p>',
  '<p><strong>Best regards,</strong><br>',
  'UBS BizApps Team<br>',
  'Group Functions</p>',
  '<hr style="border:none; border-top:1px solid #ccc; margin:20px 0;">',
  '<p style="font-size:12px; color:#999;">',
  'Please do not reply to this automatically generated email as the mailbox is not monitored.<br>',
  '© UBS ', utcNow('yyyy'), '. For internal use only.',
  '</p>',
  '</div>'
)