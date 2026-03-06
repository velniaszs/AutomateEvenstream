plan delete:
1. add correct query for deletion +
2. once deleted add data for deleted rows +
3. test if lineage +
4. if not deleted, add stuff to exception??? +
0. scripts to deploy eventhouse tables and seed data. +

2. pipeline: create alert for AOP change (specifying to what changed) +
TODO:

3. notebook: switch AOP back to original setting:
    a. try turn AOP to right setting
    b. if error, if there are items to be deleted, delete
    c. if not - list all items in workspace and recheck if there are any that would prevent turning AOP back to original setting.
    d. add them to AlertLog differently??? ( so we could still raise alerts on deleted items)
    e. delete items
    f. wait, set the AOP to right value
    g. wait, check if AOP changed
2. notebook: to get dataverse AOP setting
1. test: what error code when capacity paused??



6660419a-a6f9-41ea-bd0f-597d1f3c519b
ab_demo_2

dfe401d5-41e3-4ad9-8e82-a3886d070f3f
ab_demo_1

7d8301d0-d8af-43b8-9c35-2397c92952a8
ab_demo_3

b7c510d6-c7fb-4311-a627-8c49f3f28933
ab_demo_4



Not doing as presume access exists:
4. if error code 401??? ( no permission), add to list x??, move to other workspace items
5. for all no permission workspaces, add permission, refresh permissions, wait 1 min??

