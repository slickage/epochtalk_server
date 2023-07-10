defmodule Test.EpochtalkServerWeb.Controllers.Board do
  use Test.Support.ConnCase, async: true
  import Test.Support.Factory
  alias EpochtalkServer.Models.BoardMapping

  setup %{conn: conn} do
    category = insert(:category)

    parent_board =
      insert(:board,
        viewable_by: 10,
        postable_by: 10,
        right_to_left: false
      )
    child_board =
      insert(:board,
        viewable_by: 10,
        postable_by: 10,
        right_to_left: false
      )

    build(:board_mapping, attributes: [
      build(:board_mapping_attributes, category: category, view_order: 0),
      build(:board_mapping_attributes, board: parent_board, category: category, view_order: 1),
      build(:board_mapping_attributes, board: child_board, parent: parent_board, view_order: 2)
    ])

    {:ok, conn: conn, parent_board: parent_board, child_board: child_board, category: category}
  end

  describe "by_category/2" do
    test "finds all active boards", %{conn: conn, category: category, parent_board: board} do
      response =
        conn
        |> get(Routes.board_path(conn, :by_category))
        |> json_response(200)
        |> case do
          %{"boards" => boards} -> boards
        end

      # check number of categories
      assert Enum.count(response) == 1
      seeded_category = response |> Enum.at(0)

      # check number of boards under category
      assert seeded_category |> Map.get("boards") |> Enum.count() == 1

      # extract category/board info
      %{
        "id" => response_category_id,
        "name" => response_category_name,
        "view_order" => response_category_view_order,
        "boards" => [
          %{
            "id" => response_parent_board_id,
            "board_id" => response_parent_board_board_id,
            "name" => response_parent_board_name,
            "category_id" => response_parent_board_category_id,
            "children" => response_parent_board_children,
            "description" => response_parent_board_description,
            "view_order" => response_parent_board_view_order,
            "slug" => response_parent_board_slug,
            "viewable_by" => response_parent_board_viewable_by,
            "postable_by" => response_parent_board_postable_by,
            "right_to_left" => response_parent_board_right_to_left
          }
        ]
      } = response |> Enum.at(0)

      # test category/board info
      assert response_category_id == category.id
      assert response_category_name == category.name
      assert response_category_view_order == 0
      assert response_parent_board_id == board.id
      assert response_parent_board_board_id == board.id
      assert response_parent_board_name == board.name
      assert response_parent_board_category_id == category.id
      assert response_parent_board_children |> Enum.count() == 0
      assert response_parent_board_description == board.description
      assert response_parent_board_name == board.name
      assert response_parent_board_view_order == 1
      assert response_parent_board_slug == board.slug
      assert response_parent_board_viewable_by == board.viewable_by
      assert response_parent_board_postable_by == board.postable_by
      assert response_parent_board_right_to_left == board.right_to_left
    end
  end

  describe "find/2" do
    test "given a nonexistant id, does not find a board", %{conn: conn} do
      response =
        conn
        |> get(Routes.board_path(conn, :find, 0))
        |> json_response(400)

      assert response["error"] == "Bad Request"
      assert response["message"] == "Error, board does not exist"
    end

    test "given an existing id, finds a board", %{conn: conn, parent_board: board} do
      response =
        conn
        |> get(Routes.board_path(conn, :find, board.id))
        |> json_response(200)

      assert response["name"] == board.name
      assert response["slug"] == board.slug
      assert response["description"] == board.description
      assert response["viewable_by"] == board.viewable_by
      assert response["postable_by"] == board.postable_by
      assert response["right_to_left"] == board.right_to_left
    end
  end

  describe "slug_to_id/2" do
    test "given a nonexistant slug, does not deslugify board id", %{conn: conn} do
      response =
        conn
        |> get(Routes.board_path(conn, :slug_to_id, "bad-slug"))
        |> json_response(400)

      assert response["error"] == "Bad Request"
      assert response["message"] == "Error, cannot convert slug: board does not exist"
    end

    test "given an existing slug, deslugifies board id", %{conn: conn, parent_board: board} do
      response =
        conn
        |> get(Routes.board_path(conn, :slug_to_id, board.slug))
        |> json_response(200)

      assert response["id"] == board.id
    end
  end
end
