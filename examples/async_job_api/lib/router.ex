defmodule AsyncJobApi.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/report" do
    conn
    |> start_event_stream()
    |> enqueue_job()
    |> wait_for_job()
    |> send_response()
  end

  defp start_event_stream(conn) do
    conn
    |> put_resp_content_type("text/event-stream")
    |> send_chunked(200)
  end

  defp enqueue_job(conn) do
    id = random_id()
    Registry.register(AsyncJobApi.ConnRegistry, id, conn)

    Ecto.Multi.new()
    |> AsyncJobApi.JobQueue.enqueue("enqueue_job", %{}, notify: id)
    |> AsyncJobApi.Repo.transaction()

    Plug.Conn.assign(conn, :job_id, id)
  end

  defp wait_for_job(conn = %{assigns: %{job_id: id}}) do
    receive do
      {:job_completed, ^id} -> :ok
    end
    Registry.unregister(AsyncJobApi.ConnRegistry, id)
    conn
  end

  defp send_response(conn) do
    send_message(conn, "#{conn.assigns.job_id} completed!!!")
  end

  defp random_id do
    (1..32)
    |> Enum.map(fn _ -> :rand.uniform(?z - ?a) + ?a end)
    |> to_string()
  end

  defp send_message(conn, message) do
    {:ok, conn} = chunk(conn, "event: \"message\"\n\ndata: {\"message\": \"#{message}\"}\n\n")
    conn
  end
end