defmodule AgenticRealms.Accounts.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_themes ~w(phosphor paper dusk)
  @valid_densities ~w(comfortable compact)

  schema "players" do
    field :username, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :theme, :string, default: "phosphor"
    field :density, :string, default: "comfortable"

    timestamps(type: :utc_datetime)
  end

  @username_format ~r/^[a-zA-Z0-9_-]+$/

  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  def registration_changeset(player, attrs) do
    player
    |> cast(attrs, [:username, :password])
    |> validate_username()
    |> validate_password()
  end

  def username_changeset(player, attrs) do
    player
    |> cast(attrs, [:username])
    |> validate_username()
  end

  def preferences_changeset(player, attrs) do
    player
    |> cast(attrs, [:theme, :density])
    |> validate_inclusion(:theme, @valid_themes)
    |> validate_inclusion(:density, @valid_densities)
  end

  def password_changeset(player, attrs) do
    player
    |> cast(attrs, [:password])
    |> validate_password()
    |> hash_password()
  end

  defp validate_username(changeset) do
    changeset
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 30)
    |> validate_format(:username, @username_format,
      message: "must contain only letters, numbers, hyphens, and underscores"
    )
    |> unsafe_validate_unique(:username, AgenticRealms.Repo)
    |> unique_constraint(:username)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> hash_password()
  end

  defp hash_password(changeset) do
    password = get_change(changeset, :password)

    if password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
