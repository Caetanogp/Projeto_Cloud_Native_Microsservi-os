package br.edu.loja.notificacoes.client;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/** Cliente REST do ms-pedidos. A URL usa o nome do Service Kubernetes (Service Discovery). */
@Component
public class PedidosClient {

    private final RestClient restClient;

    public PedidosClient(@Value("${pedidos.url}") String baseUrl) {
        // HTTP/1.1 explícito: o HttpURLConnection padrão não suporta PATCH e o h2c do JDK não é necessário aqui.
        HttpClient http = HttpClient.newBuilder()
                .version(HttpClient.Version.HTTP_1_1)
                .connectTimeout(Duration.ofSeconds(3))
                .build();
        JdkClientHttpRequestFactory fabrica = new JdkClientHttpRequestFactory(http);
        fabrica.setReadTimeout(Duration.ofSeconds(5));
        this.restClient = RestClient.builder().baseUrl(baseUrl).requestFactory(fabrica).build();
    }

    public void confirmarPedido(Long pedidoId) {
        restClient.patch()
                .uri("/pedidos/{id}/status", pedidoId)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("status", "CONFIRMADO"))
                .retrieve()
                .toBodilessEntity();
    }
}
