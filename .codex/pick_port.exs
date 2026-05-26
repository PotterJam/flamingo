cwd = File.cwd!()
base = 5000
span = 20_000
start_port = base + :erlang.phash2(cwd, span)

find_port = fn find_port, port, attempts_left ->
  if attempts_left == 0 do
    raise "Unable to find open port"
  end

  free? =
    case :gen_tcp.listen(port, [
           :binary,
           active: false,
           packet: 0,
           ip: {127, 0, 0, 1},
           reuseaddr: true
         ]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end

  if free?, do: port, else: find_port.(find_port, port + 1, attempts_left - 1)
end

IO.puts(find_port.(find_port, start_port, 500))
