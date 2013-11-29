class Overpass
  def self.fabricate(sectors, types=["amenity", "shop"])
    places = []
    types.each do |t|
      places << Overpass.query(Overpass.box_coordinates(sectors), t)
    end
    places = places.flatten.compact
    places.collect! do |place|
      place = Overpass.retag place
      place = Overpass.mongoize place
    end
  end
  def self.box_coordinates(sectors)
    coordinates = sectors.map(&:coordinates).transpose
    [coordinates.first.min,coordinates.last.min,coordinates.first.max,coordinates.last.max].join(",")
  end
  def self.query(box, type)
    uri = URI.parse(URI.encode("http://www.overpass-api.de/api/xapi?node[#{type}=*][bbox=#{box}]"))
    http = Net::HTTP.new(uri.host, uri.port)
    response = http.request(Net::HTTP::Get.new(uri.request_uri))
    response = Hash.from_xml(response.body)
    response["osm"]["node"]
  end
  def self.retag(place)
    tags = place["tag"]
    if tags.class == Array
      tags.each{|i| place[i["k"]] = i["v"]}
    elsif tags.class == Hash
      place[tags["k"]] = tags["v"]
    end
    place[:overpass_id] = place["id"]
    place
  end
  def self.mongoize(place)
    place[:coordinates] = [place["lon"], place["lat"]].to_d(3).to_f
    ["tag", "id", "lat", "lon"].each{|i|place.delete i}
    place
  end
end