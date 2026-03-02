plan delete:
1. add correct query for deletion
2. once deleted add data for deleted rows
3. if not deleted, add stuff to exception???
4. if error code 401??? ( no permission), add to list x??, move to other workspace items
5. for all no permission workspaces, add permission, refresh permissions, wait 1 min??
6. test what error code when capacity paused??


plan for alert:
1. load AOP info from dataverse??
2. check table alerts vs dataverse??
3. AOP alerting
    a. check if AOP changed - alert
    b. delete not allowed items during this period
    c. delete any items that prevents turning back AOP
    d. turn back AOP
    e. check if AOP is on, if not alert