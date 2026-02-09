#update token from dev tools writing powerBIAccessToken and update accesstoken.txt

# add 1 source to eventstream.json
.\add-source.ps1 -workspaceName "ab_test3" -workspaceId "af2b1ae0-5660-454c-9952-b01cffde1d2f"
#remove the source from eventstream.json
.\remove-source.ps1 -workspaceName "ab_test3"

#create multiple sources to eventstream.json to test limits
.\run-1000-times.ps1
#limitations - 50 nodes (elements in evenstream - in our case 48 sources + stream + destinations =50)
#raised a question to product team about this limitation.
#for 4300 sources we would need to create 90 evenstreams.

#upload changes to eventstream in Fabric
.\update-eventstream.ps1 -WorkspaceId "611585cb-6332-4849-995e-efce839973f1" -EventstreamId "595ac356-b237-422f-a5d4-6c85146a3897"

#retrieve eventstream data from Fabric to eventstream.json file
.\get-eventstream.ps1 -WorkspaceId "611585cb-6332-4849-995e-efce839973f1" -EventstreamId "595ac356-b237-422f-a5d4-6c85146a3897"
########################################################
#Migration of all workspaces
#1 list workspaces and save to workspaces.json
.\list-workspaces.ps1
#2 process workspaces to add sources to eventstream.json except the Workspace, where Eventstream itself exists
.\process-workspaces.ps1
#3 upload changes to eventstream
.\update-eventstream.ps1 -WorkspaceId "611585cb-6332-4849-995e-efce839973f1" -EventstreamId "595ac356-b237-422f-a5d4-6c85146a3897"