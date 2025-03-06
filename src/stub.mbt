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
  let token = @variables.get("openai_api_key").unwrap_or_error!()
  // Get request
  let body = request.consume().unwrap()
  let content = @http.text(body).0.await!!()
  request.drop()
  // Prepare payload
  let payload : Json = {
    "model": "deepseek/deepseek-chat",
    "messages": [
      { "role": "system", "content": "You are a helpful assistant." },
      { "role": "user", "content": String(content) },
    ],
  }
  // Send request
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
  // Send response
  let response = @http.response!(200)
  let outgoing_body = response.body().unwrap()
  response_out.set(Ok(response))
  let outgoing_stream = outgoing_body.write().unwrap()
  @io.println!!(content, stream=outgoing_stream)
  outgoing_stream.drop()
  outgoing_body.finish(None).unwrap_or_error!()
}
