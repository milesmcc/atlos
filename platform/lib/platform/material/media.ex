defmodule Platform.Material.Media do
  use Ecto.Schema
  import Ecto.Changeset
  alias Platform.Utils

  schema "media" do
    # Core uneditable data
    field :slug, :string, autogenerate: &Utils.generate_media_slug/0

    # Core editable data
    field :description, :string

    # Attributes

    # Metadata
    timestamps()
    has_many :versions, Platform.Media.MediaVersion
  end

  @doc false
  def changeset(media, attrs) do
    media
    |> cast(attrs, [:description, :slug])
    |> validate_required([:description, :slug])
    |> validate_slug()
    |> unique_constraint(:slug)
  end

  defp validate_slug(changeset) do
    changeset |> validate_format(:slug, ~r/^AT[A-Z0-9]{5}$/, message: "slug is not a valid code")
  end
end