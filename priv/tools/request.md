---
name: request
mf:
  module: Livellm.Tools.Http
  function: request
schema:
  type: object
  properties:
    url:
      type: string
      description: Absolute http or https URL to request.
    method:
      type:
        - string
        - "null"
      enum:
        - GET
        - POST
        - PUT
        - PATCH
        - DELETE
        - HEAD
        - OPTIONS
      description: HTTP method. Defaults to GET.
    headers:
      type:
        - array
        - "null"
      description: Optional list of request headers. Use this for headers such as content-type.
      items:
        type: object
        properties:
          name:
            type: string
          value:
            type: string
        required:
          - name
          - value
        additionalProperties: false
    body:
      description: Optional request body. Pass raw text or a JSON-encoded string, or null.
      type:
        - string
        - "null"
  required:
    - url
    - method
    - headers
    - body
  additionalProperties: false
---
Make an HTTP request to an external URL. Supports a method, optional headers,
and an optional request body, and returns status, headers, and body content.
