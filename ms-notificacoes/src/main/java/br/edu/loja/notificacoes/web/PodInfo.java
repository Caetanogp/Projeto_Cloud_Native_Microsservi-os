package br.edu.loja.notificacoes.web;

import java.net.InetAddress;

import org.springframework.stereotype.Component;

/** Nome do Pod (Downward API no Kubernetes). Fora do cluster usa o hostname do container. */
@Component
public class PodInfo {

    private final String nome;

    public PodInfo() {
        String valor = System.getenv("POD_NAME");
        if (valor == null || valor.isBlank()) {
            try {
                valor = InetAddress.getLocalHost().getHostName();
            } catch (Exception e) {
                valor = "local";
            }
        }
        this.nome = valor;
    }

    public String nome() {
        return nome;
    }
}
