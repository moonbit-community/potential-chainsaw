///| 
/// This function is invoked with an incoming HTTP Request, and a resource
/// `response-outparam` which provides the capability to reply with an HTTP
/// Response. The response is sent by calling the `response-outparam.set`
/// method, which allows execution to continue after the response has been
/// sent. This enables both streaming to the response body, and performing other
/// work.
///
/// The implementor of this function must write a response to the
/// `response-outparam` before returning, or else the caller will respond
/// with an error on its behalf.
pub fn handle(
  request : @types.IncomingRequest,
  response_out : @types.ResponseOutparam
) -> Unit {
  @promise.spawn(async fn(_defer) {
    try {
      top!!(request, response_out)
    } catch {
      error => @io.println_sync!("Error \{error}", stream=@io.stderr)
    }
  })
  |> ignore
  @io.event_loop.run()
}

///|
async fn top(
  request : @types.IncomingRequest,
  response_out : @types.ResponseOutparam
) -> Unit! {
  // Return response to GitHub acknowledging receipt of the webhook
  let response = @http.response!(200)
  response_out.set(Ok(response))
  // Verify the header
  let headers = request.headers()
  guard headers.get("x-github-event") is [event] else {
    fail!("Expected x-github-event header")
  }
  guard @encoding.decoder(UTF8).decode!(Bytes::from_fixedarray(event))
    is "pull_request" else {
    fail!("Expected x-github-event to be pull_request")
  }
  headers.drop()
  // Parse the body
  let body = request.consume().unwrap()
  request.drop()
  let json = @http.json(body).0.await!!()
  guard json
    is {
      "action": "opened"
      | "synchronize",
      "repository": {
        "name": String(repository),
        "owner": { "login": String(owner), .. },
        ..
      },
      "installation": { "id": Number(installation), .. },
      "pull_request": {
        "number": Number(pull_request),
        "body"? : pull_request_message,
        ..
      },
      ..
    }
  // Get the Pull Request message
  let pull_request_message = if pull_request_message is Some(String(message)) {
    message
  } else {
    ""
  }
  let environment = Map::from_array(@environment.get_environment())
  guard environment["CLIENT_ID"] is Some(client_id)
  guard environment["PRIVATE_KEY"] is Some(private_key)
  guard environment["USER_NAME"] is Some(username)
  let now = @wallClock.now().seconds
  let token = create_installation_access_token!!(
    installation.to_uint(),
    private_key,
    client_id,
    now,
    username,
  )
  // Get the Pull Request's changes
  let pull_request_diff = get_pr_diff!!(
    owner,
    repository,
    pull_request.to_int64(),
    token,
    username,
  )
  @io.println!!(
    #|=== Pull Request Message ==
    $|\{pull_request_message}
    #|=== Pull Request Changes (in diff format) ==
    $|\{pull_request_diff}
    ,
  )
}

///|
async fn create_installation_access_token(
  installation : UInt,
  private_key : String,
  client_id : String,
  now : UInt64,
  username : String
) -> String! {
  let jwt = @jwt.sign_rs256(
    {
      "iat": Number((now - 60).to_double()),
      "exp": Number((now + 600).to_double()),
      "iss": String(client_id),
    },
    private_key,
  )
  let request = @http.request!(
    "api.github.com",
    method_=Post,
    path="/app/installations/\{installation}/access_tokens",
    headers=@http.headers({
      "Accept": ["application/vnd.github.v3+json"],
      "X-GitHub-Api-Version": ["2022-11-28"],
      "User-Agent": [@encoding.encode(UTF8, username)],
      "Authorization": [@encoding.encode(UTF8, "Bearer \{jwt}")],
    }),
  )
  let response = @http.fetch!!(request)
  if response.status() != 201 {
    let body = response.consume().unwrap()
    let content = @http.text(body).0.await!!()
    fail!("Failed to create installation access token. Reason: \{content}")
  }
  let body = response.consume().unwrap()
  let json = @http.json(body).0.await!!()
  guard json is { "token": String(token), .. } else {
    fail!("Failed to create installation access token. Reason: \{json}")
  }
  token
}

///|
async fn get_pr_diff(
  owner : String,
  repo : String,
  pull_number : Int64,
  token : String,
  username : String
) -> String! {
  let request = @http.request!(
    "api.github.com",
    path="/repos/\{owner}/\{repo}/pulls/\{pull_number}",
    headers=@http.headers({
      "Accept": [b"application/vnd.github.v3.diff"],
      "Authorization": [@encoding.encode(UTF8, "token \{token}")],
      "User-Agent": [@encoding.encode(UTF8, username)],
    }),
  )
  let response = @http.fetch!!(request)
  if response.status() != 200 {
    let body = response.consume().unwrap()
    let content = @http.text(body).0.await!!()
    response.drop()
    raise fail!("Error fetching diff \{response.status()}: \{content}")
  }
  let body = response.consume().unwrap()
  let content = @http.text(body).0.await!!()
  response.drop()
  content
}
