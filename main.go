package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"strconv"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/push"
)

type Response struct {
	Stacja              string
	Data_pomiaru        string
	Godzina_pomiaru     string
	Temperatura         string
	Predkosc_wiatru     string
	Kierunek_wiatru     string
	Wilgotnosc_wzgledna string
	Suma_opadu          string
	Cisnienie           string
}

// change string data floats for later processing
func string2float(data_in string) float64 {
	data_out, err := strconv.ParseFloat(data_in, 64)
	if err != nil {
		log.Fatal(err)
	}
	return data_out
}

func isNumeric(s string) bool {
	_, err := strconv.ParseFloat(s, 64)
	return err == nil
}

// calculate wind speed in beuforts
func ms2b(wspeed_ms string) string {
	ret := strconv.FormatFloat(math.Round(string2float(wspeed_ms)*1.126840655625), 'g', 5, 64)
	return ret
}

func init() {
	file, err := os.OpenFile("caller.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0755)
	if err != nil {
		log.Fatal(err)
	}
	log.SetOutput(file)
}

var (
	temp = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "degc_air_temp",
		Help: "Temperature measured in weather station",
	})
	pres = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "hpa_air_press",
		Help: "Pressure measured in weather station",
	})
	rain = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "mm_rain",
		Help: "Rain measured in weather station",
	})
	wind = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "beufort_wind",
		Help: "Wind measured in weather station",
	})
)

func main() {

	PUSHGW_ENDPOINT := os.Getenv("PUSHGW")
	STATION_ID := os.Getenv("STATIONID")
	if !isNumeric(STATION_ID) {
		log.Fatal("Parameter not numeric")
	}
	requestURL := fmt.Sprintf("https://danepubliczne.imgw.pl/api/data/synop/id/%s", STATION_ID)
	response, err := http.Get(requestURL)
	if err != nil {
		log.Fatal(err)
	}
	responseData, err := io.ReadAll(response.Body)
	if err != nil {
		log.Fatal(err)
	}
	var responseObject Response
	json.Unmarshal(responseData, &responseObject) //unmarshall structa
	temp.Set(string2float(responseObject.Temperatura))
	pres.Set(string2float(responseObject.Cisnienie))
	rain.Set(string2float(responseObject.Suma_opadu))
	wind.Set(string2float(ms2b(responseObject.Predkosc_wiatru)))
	registry := prometheus.NewRegistry()
	registry.MustRegister(temp, pres, rain, wind)
	pusher := push.New(PUSHGW_ENDPOINT, "imgw_archiver").Grouping("loc", responseObject.Stacja).Gatherer(registry)
	if err := pusher.Add(); err != nil {
		fmt.Println("Could not push to Pushgateway:", err)
	}
}
