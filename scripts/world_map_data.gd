class_name WorldMapData
extends RefCounted

## Grafo do overworld (docs/CAMPAIGN_EXECUTION_PLAN.md, Passo 1.2): pontos
## de interesse + conexões entre eles, carregado de data/world/*.json.
## Catálogo puro — nunca muda durante a campanha; onde o jogador está e o
## que ele já fez ficam no estado de campanha.

const DEFAULT_PATH = "res://data/world/overworld.json"

## id -> WorldPointData.
var points: Dictionary = {}

## Pares [id_a, id_b], sem direção — uma conexão sempre pode ser percorrida
## nos dois sentidos (exploração livre, ir e voltar).
var connections: Array[PackedStringArray] = []

## Ponto onde uma campanha nova começa (usado a partir do Passo 1.3).
var start_point_id: String = ""

static func from_dict(data: Dictionary) -> WorldMapData:
	var map = WorldMapData.new()

	for point_data in data.get("points", []):
		var point = WorldPointData.from_dict(point_data)

		if point.id == "" or map.points.has(point.id):
			print("Ponto de mapa sem id ou repetido: ", point_data)
			continue

		map.points[point.id] = point

	## Conexão que cita um ponto inexistente é descartada com aviso, em
	## vez de quebrar o desenho do mapa — mesmo espírito dos databases,
	## que pulam um JSON inválido e seguem carregando o resto.
	for connection in data.get("connections", []):
		if connection.size() != 2 or not map.points.has(connection[0]) or not map.points.has(connection[1]):
			print("Conexão de mapa inválida: ", connection)
			continue

		map.connections.append(PackedStringArray([connection[0], connection[1]]))

	map.start_point_id = data.get("start_point", "")

	if not map.points.has(map.start_point_id):
		print("Ponto inicial do mapa inválido: ", map.start_point_id)

	return map

## Conexões não têm direção — a ordem dos ids no par não importa.
func are_connected(point_a_id: String, point_b_id: String) -> bool:
	for connection in connections:
		if (connection[0] == point_a_id and connection[1] == point_b_id) or (connection[0] == point_b_id and connection[1] == point_a_id):
			return true

	return false

## Um único mapa por enquanto, então não há um database com vários —
## só este carregamento direto de um arquivo.
static func load_from_file(path: String = DEFAULT_PATH) -> WorldMapData:
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Não consegui abrir: ", path)
		return WorldMapData.new()

	var data = JSON.parse_string(file.get_as_text())

	if data == null or not data is Dictionary:
		print("JSON inválido: ", path)
		return WorldMapData.new()

	var map = from_dict(data)

	print("Mapa carregado: ", path, " (", map.points.size(), " pontos, ", map.connections.size(), " conexões)")

	return map
