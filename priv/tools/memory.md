---
name: memory
mf:
  module: Livellm.Memories.Tool
  function: manage_memory
schema:
  type: object
  properties:
    action:
      type: string
      enum:
        - list
        - get
        - multiget
        - search
        - write
        - delete
      description: "list: all memory ids and titles; get: one by id; multiget: fetch several full memories by ids; search: by text; write: save new or update existing; delete: remove one by id."
    id:
      type:
        - integer
        - "null"
      description: Id of the memory to retrieve (get), update (write), or delete. Omit or null when creating new.
    ids:
      type:
        - array
        - "null"
      items:
        type: integer
      description: List of memory ids for multiget. Use this when you need the full content of multiple memories.
    data:
      type:
        - string
        - "null"
      description: Search text for search. Content to save for write. Omit for list and get.
    title:
      type:
        - string
        - "null"
      description: Title for write. Required when creating; optional when updating.
  additionalProperties: false
  required:
    - action
    - id
    - ids
    - data
    - title
---
Manage user memories: list summaries, get one by id, multiget several by ids,
search by text, write (create or update), or delete.
