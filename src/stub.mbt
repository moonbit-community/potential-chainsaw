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
  guard environment["APP_ID"] is Some(app_id)
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
  let review = get_review!!(pull_request_message, pull_request_diff)
  let comment_id = get_comment_list!!(
    owner,
    repository,
    pull_request.to_int64(),
    token,
    app_id,
    username,
  )
  if comment_id is Some(id) {
    update_comment!!(owner, repository, id, review, token, username)
  } else {
    create_comment!!(
      owner,
      repository,
      pull_request.to_int64(),
      review,
      token,
      username,
    )
  }
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

///|
async fn get_review(message : String, changes : String) -> String! {
  guard Map::from_array(@environment.get_environment()).get("OPENAI_API_KEY")
    is Some(token) else {
    fail!("OPENAI_API_KEY is not set")
  }
  let system_msg =
    #|You are a programmer conducting code review.
    #|Based on the pull request message and changes, provide feedback.
    #|
    #|Point out at most three problems that you observe
  let user_msg =
    #|=== Pull Request Message ==
    $|\{message}
    #|=== Pull Request Changes (in diff format) ==
    $|\{changes}
  let payload : Json = {
    "model": "deepseek/deepseek-chat",
    "messages": [
      { "role": "system", "content": String(system_msg) },
      { "role": "user", "content": String(user_msg) },
    ],
  }
  let request = @http.request!(
    "openrouter.ai",
    path="/api/v1/chat/completions",
    scheme=Https,
    method_=Post,
    headers=@http.headers({
      "Content-Type": ["application/json"],
      "Authorization": [@encoding.encode(UTF8, "Bearer \{token}")],
    }),
  )
  let body = request.body().unwrap()
  let output_stream = body.write().unwrap()
  @io.println!!(payload.stringify(), stream=output_stream)
  output_stream.drop()
  body.finish(None).unwrap_or_error!()
  let response = @http.fetch!!(request)
  let body = response.consume().unwrap()
  let content = @http.json(body).0.await!!()
  response.drop()
  guard content
    is {
      "choices": [{ "message": { "content": String(content), .. }, .. }],
      ..
    } else {
    fail!("Unexpected response \{content}")
  }
  content
}

///|
async fn get_comment_list(
  owner : String,
  repo : String,
  issue_number : Int64,
  token : String,
  app_id : String,
  username : String
) -> Int64?! {
  let request = @http.request?(
    "api.github.com",
    path="/repos/\{owner}/\{repo}/issues/\{issue_number}/comments",
    headers=@http.headers({
      "Accept": [b"application/vnd.github.v3+json"],
      "Authorization": [@encoding.encode(UTF8, "token \{token}")],
      "User-Agent": [@encoding.encode(UTF8, username)],
    }),
  ).unwrap()
  let response = @http.fetch!!(request)
  if response.status() != 200 {
    let body = response.consume().unwrap()
    let content = @http.text(body).0.await!!()
    response.drop()
    fail!("Failed to list issue comments. Reason: \{content}")
  }
  let body = response.consume().unwrap()
  let json = @http.json(body).0.await!!()
  response.drop()
  guard json is Array(comments) else {
    fail!("Failed to list issue comments. Unexpected response: \{json}")
  }
  for comment in comments {
    if comment
      is {
        "performed_via_github_app": { "id": Number(github_app_id), .. },
        "id": Number(comment_id),
        ..
      } &&
      github_app_id.to_int64().to_string() == app_id {
      return Some(comment_id.to_int64())
    }
  } else {
    return None
  }
}

///|
async fn create_comment(
  owner : String,
  repo : String,
  issue_number : Int64,
  comment : String,
  token : String,
  username : String
) -> Unit! {
  let request = @http.request?(
    "api.github.com",
    path="/repos/\{owner}/\{repo}/issues/\{issue_number}/comments",
    method_=Post,
    headers=@http.headers({
      "Accept": ["application/vnd.github.v3+json"],
      "Authorization": [@encoding.encode(UTF8, "token \{token}")],
      "X-Github-Api-Version": ["2022-11-28"],
      "User-Agent": [@encoding.encode(UTF8, username)],
    }),
  ).unwrap()
  let body = request.body().unwrap()
  let output = body.write().unwrap()
  @io.println!!(({ "body": String(comment) } : Json).stringify(), stream=output)
  output.drop()
  body.finish(None).unwrap()
  let response = @http.fetch!!(request)
  if response.status() != 201 {
    let body = response.consume().unwrap()
    let content = @http.text(body).0.await!!()
    response.drop()
    fail!("Failed to create comment. Reason: \{content}")
  }
  response.drop()
}

///|
async fn update_comment(
  owner : String,
  repo : String,
  comment_id : Int64,
  comment : String,
  token : String,
  username : String
) -> Unit! {
  let request = @http.request?(
    "api.github.com",
    path="/repos/\{owner}/\{repo}/issues/comments/\{comment_id}",
    method_=Patch,
    headers=@http.headers({
      "Accept": ["application/vnd.github.v3+json"],
      "Authorization": [@encoding.encode(UTF8, "token \{token}")],
      "X-Github-Api-Version": ["2022-11-28"],
      "User-Agent": [@encoding.encode(UTF8, username)],
    }),
  ).unwrap()
  let body = request.body().unwrap()
  let output = body.write().unwrap()
  @io.println!!(({ "body": String(comment) } : Json).stringify(), stream=output)
  output.drop()
  body.finish(None).unwrap()
  let response = @http.fetch!!(request)
  if response.status() != 200 {
    let body = response.consume().unwrap()
    let content = @http.text(body).0.await!!()
    response.drop()
    fail!("Failed to update comment. Reason: \{content}")
  }
  response.drop()
}
