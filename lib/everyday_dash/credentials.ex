defmodule EverydayDash.Credentials do
  @moduledoc false

  @encryption_salt "everyday_dash:credentials:enc"
  @signing_salt "everyday_dash:credentials:sign"

  def encrypt(payload) when is_map(payload) do
    with {:ok, key_base} <- key_base() do
      plaintext = Jason.encode!(payload)

      ciphertext =
        Plug.Crypto.MessageEncryptor.encrypt(
          plaintext,
          derive(key_base, @encryption_salt),
          derive(key_base, @signing_salt)
        )

      {:ok, ciphertext}
    end
  end

  def decrypt(nil), do: {:ok, %{}}

  def decrypt(ciphertext) when is_binary(ciphertext) do
    with {:ok, key_base} <- key_base(),
         {:ok, plaintext} <-
           Plug.Crypto.MessageEncryptor.decrypt(
             ciphertext,
             derive(key_base, @encryption_salt),
             derive(key_base, @signing_salt)
           ),
         {:ok, payload} <- Jason.decode(plaintext) do
      {:ok, payload}
    else
      :error -> {:error, :invalid_ciphertext}
      {:error, _reason} = error -> error
    end
  end

  defp key_base do
    case Application.get_env(:everyday_dash, __MODULE__, [])[:secret] do
      secret when is_binary(secret) and byte_size(secret) >= 32 -> {:ok, secret}
      _missing -> {:error, :missing_secret}
    end
  end

  defp derive(secret, salt) do
    Plug.Crypto.KeyGenerator.generate(secret, salt, iterations: 1_000, length: 32)
  end
end
