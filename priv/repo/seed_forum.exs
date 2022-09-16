alias EpochtalkServer.Models.Category
alias EpochtalkServer.Models.Board

category_name = "General"
category = %Category{
  name: category_name
}

board_name = "General Discussion"
board_description = "Every forum's got one; talk about anything here"
board_slug = "general-discussion"
board = %Board{
  name: board_name,
  description: board_description,
  slug: board_slug
}

seeded_category = Category.insert(category)
|> case do
  {:ok, c} -> c
  _ ->
    IO.puts("Seed failed, unable to create Category with name #{category_name}")
    Process.exit(self, :normal)
end

seeded_board = Board.insert(board)
|> case do
  {:ok, b} -> b
  _ ->
    IO.puts("Seed failed, unable to create Board #{board_name}, #{board_description}")
    Process.exit(self, :normal)
end
