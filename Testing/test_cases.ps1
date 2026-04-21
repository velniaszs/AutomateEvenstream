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


find_replace:
  - find_value: "611585cb-6332-4849-995e-efce839973f1" #Workspace GUID to find
    replace_value:
      DEV: "dfe401d5-41e3-4ad9-8e82-a3886d070f3f"
      TEST: "dfe401d5-41e3-4ad9-8e82-a3886d070f3f"
      PROD: "dfe401d5-41e3-4ad9-8e82-a3886d070f3f"
    item_type: ["Notebook"]

  - find_value: "0160fd4d-7e00-4c5e-8995-4a9174b13b63" #Lakehouse AopConfigLH GUID to find
    replace_value:
      DEV: "07e72d95-7550-4b18-a9d2-52e2e69b4830"
      TEST: "07e72d95-7550-4b18-a9d2-52e2e69b4830"
      PROD: "07e72d95-7550-4b18-a9d2-52e2e69b4830" 
    item_type: ["Notebook"]

  - find_value: "https://trd-6uegjpfbf030eemxtw.z1.kusto.fabric.microsoft.com" #kusto cluster uri to find
    replace_value:
      DEV: "https://trd-6uegjpfbf030eemxtw.z1.kusto.fabric.microsoft.com"
      TEST: "https://trd-6uegjpfbf030eemxtw.z1.kusto.fabric.microsoft.com"
      PROD: "https://trd-6uegjpfbf030eemxtw.z1.kusto.fabric.microsoft.com"
    item_type: ["Notebook"]
