; =====================================================================
; PROYECTO: Sistema de Ventas e Inventario para Papeleria
; Captura con ReadString, salida con WriteString, conversiones propias.
;
; RESUMEN GENERAL:
;   Programa de consola en ensamblador x86 (MASM + libreria Irvine32).
;   Maneja un catalogo de hasta 10 productos en memoria, con menu para
;   registrar, consultar/buscar, recibir mercancia, vender (con descuento
;   por mayoreo), ver resumen y guardar/cargar el inventario en disco.
;   Los precios se manejan en CENTAVOS (enteros) para evitar decimales.
; =====================================================================
INCLUDE Irvine32.inc                ; Libreria Irvine32 (WriteString, ReadString, archivos, etc.)

; ---------------------------------------------------------------------
; Constantes del programa
; ---------------------------------------------------------------------
MAX_PRODUCTOS EQU 10                ; Maximo de productos que caben en el catalogo
TAM_PRODUCTO  EQU 42   ; 8 (codigo) + 26 (nombre) + 4 (precio) + 4 (existencia)
TAM_INVENTARIO EQU 420 ; TAM_PRODUCTO * MAX_PRODUCTOS

.data
    ; -----------------------------------------------------------------
    ; Estructura de datos principal
    ; -----------------------------------------------------------------
    ; Registro: [Codigo:8 @0][Nombre:26 @8][Precio centavos:DWORD @34][Existencia:DWORD @38]
    ; (los numeros @ son el desplazamiento en bytes dentro de cada registro)
    Inventario     BYTE 420 DUP(0)  ; Arreglo de 10 registros de 42 bytes, inicia en ceros
    TotalProductos DWORD 0          ; Cuantos productos hay registrados actualmente
    IngresosSesion DWORD 0          ; Dinero acumulado por ventas (en centavos)
    ptrProducto    DWORD 0          ; Guarda temporalmente la direccion del producto elegido
    totalVenta     DWORD 0          ; Total cobrado en la ultima venta (centavos)
    aplicoDesc     DWORD 0          ; Bandera: 1 si la venta tuvo descuento de mayoreo

    ; Temporales de captura (el registro se escribe solo si todo es valido)
    codTmp         BYTE 8 DUP(0)    ; Codigo capturado (7 caracteres + terminador 0)
    nomTmp         BYTE 26 DUP(0)   ; Nombre capturado
    precioTmp      DWORD 0          ; Precio capturado ya convertido a centavos
    existTmp       DWORD 0          ; Existencia capturada

    ; Temporales para cargar archivo (se valida aqui antes de reemplazar el catalogo real)
    tmpTotal       DWORD 0          ; Total de productos leido del archivo
    tmpInv         BYTE 420 DUP(0)  ; Inventario leido del archivo

    ; -----------------------------------------------------------------
    ; Archivo y sus mensajes
    ; -----------------------------------------------------------------
    NombreArchivo  BYTE "inventario.dat", 0     ; Nombre del archivo en disco
    fileHandle     HANDLE ?                     ; Identificador del archivo abierto
    errorArchivo   BYTE "Error: archivo ausente, danado o invalido. Se conserva el catalogo actual.", 0Dh, 0Ah, 0
    errorGuardar   BYTE "Error al guardar el archivo de disco.", 0Dh, 0Ah, 0
    msgCargado     BYTE "Catalogo cargado exitosamente desde disco.", 0Dh, 0Ah, 0
    msgGuardado    BYTE "Catalogo guardado exitosamente en disco.", 0Dh, 0Ah, 0
    msgSinArchivo  BYTE "No se encontro inventario.dat (catalogo vacio).", 0Dh, 0Ah, 0
    ; Submenu de archivo (0Dh,0Ah = salto de linea)
    msgSubArchivo  BYTE 0Dh, 0Ah, "1. Guardar inventario", 0Dh, 0Ah,
                        "2. Cargar inventario", 0Dh, 0Ah,
                        "Opcion: ", 0

    ; -----------------------------------------------------------------
    ; Menu principal
    ; -----------------------------------------------------------------
    msgTitulo      BYTE "=== SISTEMA DE INVENTARIO - PAPELERIA ===", 0
    msgMenu        BYTE 0Dh, 0Ah, "1. Registrar producto", 0Dh, 0Ah,
                        "2. Consultar inventario y buscar", 0Dh, 0Ah,
                        "3. Recibir mercancia", 0Dh, 0Ah,
                        "4. Vender producto (con mayoreo)", 0Dh, 0Ah,
                        "5. Mostrar resumen e ingresos", 0Dh, 0Ah,
                        "6. Guardar y Cargar archivo", 0Dh, 0Ah,
                        "7. Salir", 0Dh, 0Ah,
                        "Seleccione una opcion: ", 0
    msgOpcionInv   BYTE "Opcion invalida. Intente de nuevo.", 0Dh, 0Ah, 0

    ; Mensajes de alta (registro de producto)
    msgCodIng      BYTE "Ingrese codigo: ", 0
    msgNomIng      BYTE "Ingrese nombre (1 a 25 caracteres): ", 0
    msgPreIng      BYTE "Ingrese precio en pesos (0.01 a 9999.99, Ej. 18.50): ", 0
    msgExiIng      BYTE "Ingrese existencia inicial (0-100): ", 0
    msgErrCap      BYTE "Error: Capacidad maxima alcanzada (10).", 0Dh, 0Ah, 0
    msgErrDup      BYTE "Error: El codigo ya existe en el sistema.", 0Dh, 0Ah, 0
    msgErrCod      BYTE "Error: codigo invalido. Use 3 letras mayusculas, guion y 3 digitos.", 0Dh, 0Ah, 0
    msgErrNom      BYTE "Error: el nombre debe tener de 1 a 25 caracteres.", 0Dh, 0Ah, 0
    msgErrPre      BYTE "Error: precio invalido (0.01 a 9999.99, sin simbolos).", 0Dh, 0Ah, 0
    msgErrExi      BYTE "Error: existencia invalida (entero de 0 a 100).", 0Dh, 0Ah, 0
    msgExitoAlta   BYTE "Producto registrado exitosamente.", 0Dh, 0Ah, 0

    ; Mensajes de recepcion de mercancia
    msgCantRec     BYTE "Unidades a recibir: ", 0
    msgExitoRec    BYTE "Mercancia recibida. Existencia actualizada.", 0Dh, 0Ah, 0
    msgErrExceso   BYTE "Error: la existencia no puede pasar de 100 unidades.", 0Dh, 0Ah, 0

    ; Mensajes de venta
    msgCantVenta   BYTE "Cantidad a vender: ", 0
    msgVentaOk     BYTE "Venta realizada correctamente.", 0Dh, 0Ah, 0
    msgDescuento   BYTE "Se aplico 10% de descuento por mayoreo (10 o mas piezas).", 0Dh, 0Ah, 0
    msgTotalVenta  BYTE "Total cobrado: ", 0
    msgSinStock    BYTE "Error: existencia insuficiente.", 0Dh, 0Ah, 0
    msgErrCant     BYTE "Error: cantidad invalida (entero mayor que cero).", 0Dh, 0Ah, 0
    msgDesborde    BYTE "Error: desbordamiento en el calculo. Venta rechazada.", 0Dh, 0Ah, 0

    ; Mensajes de busqueda y listado
    msgListHead    BYTE 0Dh, 0Ah, "--- CATALOGO DE PAPELERIA ---", 0Dh, 0Ah, 0
    msgResHead     BYTE 0Dh, 0Ah, "--- RESUMEN ---", 0Dh, 0Ah, 0
    msgCodProd     BYTE "Ingrese codigo del producto: ", 0
    msgBusqOpc     BYTE "Codigo a buscar (ENTER para omitir): ", 0
    msgNoEncontr   BYTE "Producto no encontrado.", 0Dh, 0Ah, 0
    msgInvVacio    BYTE "El inventario esta vacio.", 0Dh, 0Ah, 0
    msgAlertaMin   BYTE " [ALERTA: Existencia baja <= 5]", 0
    msgSepPrecio   BYTE " | Precio: ", 0
    msgSepExist    BYTE " | Existencia: ", 0

    ; Mensajes del resumen
    msgResProd     BYTE "Productos registrados: ", 0
    msgResUnid     BYTE "Unidades disponibles: ", 0
    msgResValor    BYTE "Valor total del inventario: ", 0
    msgResIngr     BYTE "Ingresos de la sesion: ", 0

    ; Cadenas pequenas para armar el formato de precio "$18.50 MXN"
    strDolar       BYTE "$", 0
    strPunto       BYTE ".", 0
    strCero        BYTE "0", 0
    strEspacio     BYTE " ", 0
    etiquetaMXN    BYTE " MXN", 0

    ; Buffers
    bufferIn       BYTE 30 DUP(0)   ; Buffer donde ReadString guarda lo que escribe el usuario
    bufNum         BYTE 12 DUP(0)   ; Buffer para convertir un numero a texto al imprimirlo

.code
; =====================================================================
; PROGRAMA PRINCIPAL: carga el inventario y muestra el menu en ciclo
; =====================================================================
main PROC
    cld                             ; Direccion de cadenas hacia adelante (para rep movsb, etc.)
    call ClrScr                     ; Limpia la pantalla
    call CargarInventario           ; Intenta cargar inventario.dat al iniciar

MenuPrincipal:
    call Crlf
    mov edx, OFFSET msgTitulo
    call WriteString                ; Muestra el titulo
    mov edx, OFFSET msgMenu         ; EDX = texto del menu (LeerEntero lo imprime)
    call LeerEntero                 ; Muestra el menu y lee la opcion -> EAX
    jc OpcionInvalida               ; CF=1 significa que no era un numero valido

    ; Despacho segun la opcion elegida
    cmp eax, 1
    je OpRegistrar
    cmp eax, 2
    je OpConsultar
    cmp eax, 3
    je OpRecibir
    cmp eax, 4
    je OpVender
    cmp eax, 5
    je OpResumen
    cmp eax, 6
    je OpArchivoMenu
    cmp eax, 7
    je SalirPrograma

OpcionInvalida:                     ; Llega aqui si no coincidio con ninguna opcion
    mov edx, OFFSET msgOpcionInv
    call WriteString
    jmp MenuPrincipal

; Cada opcion llama a su procedimiento y regresa al menu
OpRegistrar:
    call RegistrarProducto
    jmp MenuPrincipal
OpConsultar:
    call ConsultarInventario
    jmp MenuPrincipal
OpRecibir:
    call RecibirMercancia
    jmp MenuPrincipal
OpVender:
    call VenderProducto
    jmp MenuPrincipal
OpResumen:
    call MostrarResumen
    jmp MenuPrincipal
OpArchivoMenu:                      ; Submenu: 1 = guardar, 2 = cargar
    mov edx, OFFSET msgSubArchivo
    call LeerEntero
    jc OpcionInvalida
    cmp eax, 1
    je SubGuardar
    cmp eax, 2
    je SubCargar
    jmp OpcionInvalida
SubGuardar:
    call GuardarInventario
    jmp MenuPrincipal
SubCargar:
    call CargarInventario
    jmp MenuPrincipal

SalirPrograma:
    exit                            ; Termina el programa (macro de Irvine32)
main ENDP

; =====================================================================
; 1. REGISTRAR PRODUCTO
; Pide codigo, nombre, precio y existencia. Cada dato se valida y se
; guarda en variables temporales; el registro se escribe en el
; inventario solo si TODOS los datos son validos.
; =====================================================================
RegistrarProducto PROC
    pushad                          ; Guarda todos los registros (se restauran con popad)

    cmp TotalProductos, MAX_PRODUCTOS
    jae L_CapLlena                  ; Si ya hay 10 o mas, no se puede registrar otro

    ; ---- Codigo: 3 letras mayusculas, guion, 3 digitos ----
    call LimpiarBuffer              ; Pone en ceros el buffer de captura
    mov edx, OFFSET msgCodIng
    call WriteString
    mov edx, OFFSET bufferIn        ; EDX = donde guardar el texto
    mov ecx, 29                     ; ECX = maximo de caracteres a leer
    call ReadString                 ; EAX = cantidad de caracteres escritos
    cmp eax, 7                      ; El codigo debe medir exactamente 7 (ej. ABC-123)
    jne L_ErrCod
    mov esi, OFFSET bufferIn
    call ValidarCodigoEn            ; Verifica el formato LLL-DDD
    jc L_ErrCod

    call BuscarProductoPorCodigo    ; ESI = registro existente o 0
    cmp esi, 0
    jne L_Duplicado                 ; Si lo encontro, el codigo ya existe

    ; guardar codigo en temporal (7 caracteres + 0)
    mov esi, OFFSET bufferIn
    mov edi, OFFSET codTmp
    mov ecx, 8
    rep movsb                       ; Copia 8 bytes de bufferIn a codTmp

    ; ---- Nombre (1 a 25) ----
    call LimpiarBuffer
    mov edx, OFFSET msgNomIng
    call WriteString
    mov edx, OFFSET bufferIn
    mov ecx, 29
    call ReadString
    cmp eax, 1
    jb L_ErrNom                     ; Menos de 1 caracter: invalido
    cmp eax, 25
    ja L_ErrNom                     ; Mas de 25 caracteres: invalido
    mov esi, OFFSET bufferIn
    mov edi, OFFSET nomTmp
    mov ecx, 26
    rep movsb                       ; Copia el nombre al temporal

    ; ---- Precio ----
    call LimpiarBuffer
    mov edx, OFFSET msgPreIng
    call WriteString
    mov edx, OFFSET bufferIn
    mov ecx, 29
    call ReadString
    call StringACentavos            ; Convierte "18.50" a 1850 en EAX
    jc L_ErrPre                     ; CF=1: formato o rango invalido
    mov precioTmp, eax

    ; ---- Existencia ----
    mov edx, OFFSET msgExiIng
    call LeerEntero                 ; Muestra el mensaje y lee un entero -> EAX
    jc L_ErrExi
    cmp eax, 100
    ja L_ErrExi                     ; Maximo 100 unidades
    mov existTmp, eax

    ; ---- Todo valido: escribir el registro completo ----
    call ObtenerPunteroLibre        ; ESI = direccion del siguiente registro libre
    mov edi, esi                    ; EDI = destino
    mov esi, OFFSET codTmp
    mov ecx, 8
    rep movsb                       ; Escribe codigo (offset 0)
    mov esi, OFFSET nomTmp
    mov ecx, 26
    rep movsb                       ; Escribe nombre (offset 8)
    mov eax, precioTmp
    stosd                           ; Escribe precio, 4 bytes (offset 34)
    mov eax, existTmp
    stosd                           ; Escribe existencia, 4 bytes (offset 38)

    inc TotalProductos              ; Un producto mas en el catalogo
    mov edx, OFFSET msgExitoAlta
    call WriteString
    jmp L_FinReg

; --- Manejo de errores: cada etiqueta carga su mensaje en EDX y se imprime en L_Mostrar ---
L_CapLlena:
    mov edx, OFFSET msgErrCap
    jmp L_Mostrar
L_Duplicado:
    mov edx, OFFSET msgErrDup
    jmp L_Mostrar
L_ErrCod:
    mov edx, OFFSET msgErrCod
    jmp L_Mostrar
L_ErrNom:
    mov edx, OFFSET msgErrNom
    jmp L_Mostrar
L_ErrPre:
    mov edx, OFFSET msgErrPre
    jmp L_Mostrar
L_ErrExi:
    mov edx, OFFSET msgErrExi
L_Mostrar:
    call WriteString

L_FinReg:
    popad                           ; Restaura los registros
    ret
RegistrarProducto ENDP

; =====================================================================
; 2. CONSULTAR INVENTARIO Y BUSQUEDA
; Lista todos los productos y permite buscar uno por codigo (opcional).
; =====================================================================
ConsultarInventario PROC
    pushad
    mov edx, OFFSET msgListHead
    call WriteString

    mov ecx, TotalProductos         ; ECX = cuantos productos recorrer
    cmp ecx, 0
    je L_Vacio                      ; Si no hay productos, avisa y termina

    mov esi, OFFSET Inventario      ; ESI apunta al primer registro
L_LoopList:
    call ImprimirProducto           ; Imprime el registro apuntado por ESI
    add esi, TAM_PRODUCTO           ; Avanza al siguiente registro (42 bytes)
    loop L_LoopList                 ; Decrementa ECX y repite mientras no sea 0

    ; Busqueda opcional por codigo
    call Crlf
    call LimpiarBuffer
    mov edx, OFFSET msgBusqOpc
    call WriteString
    mov edx, OFFSET bufferIn
    mov ecx, 29
    call ReadString
    cmp eax, 0
    je L_FinCons                    ; Solo presiono ENTER: omite la busqueda
    cmp eax, 7
    jne L_BusqNo                    ; Longitud distinta de 7: no puede ser un codigo
    mov esi, OFFSET bufferIn
    call ValidarCodigoEn
    jc L_BusqNo
    call BuscarProductoPorCodigo
    cmp esi, 0
    je L_BusqNo                     ; No existe
    call ImprimirProducto           ; Lo encontro: lo imprime
    jmp L_FinCons

L_BusqNo:
    mov edx, OFFSET msgNoEncontr
    call WriteString
    jmp L_FinCons

L_Vacio:
    mov edx, OFFSET msgInvVacio
    call WriteString

L_FinCons:
    popad
    ret
ConsultarInventario ENDP

; Imprime una linea con el producto apuntado por ESI
; Formato: CODIGO Nombre | Precio: $X.XX MXN | Existencia: N [alerta]
ImprimirProducto PROC
    pushad
    mov edx, esi
    call WriteString              ; codigo (los primeros bytes del registro)
    mov edx, OFFSET strEspacio
    call WriteString

    mov edx, esi
    add edx, 8
    call WriteString              ; nombre (offset 8 del registro)

    mov edx, OFFSET msgSepPrecio
    call WriteString
    mov eax, [esi + 34]           ; precio en centavos
    call MostrarPrecioMXN

    mov edx, OFFSET msgSepExist
    call WriteString
    mov eax, [esi + 38]           ; existencia
    call ImprimirEntero           ; (conserva EAX porque usa pushad/popad)

    ; Regla de negocio: alerta de existencia minima (<= 5)
    cmp eax, 5
    ja L_SinAlerta                ; Si hay mas de 5, no hay alerta
    mov edx, OFFSET msgAlertaMin
    call WriteString
L_SinAlerta:
    call Crlf
    popad
    ret
ImprimirProducto ENDP

; =====================================================================
; 3. RECIBIR MERCANCIA
; Suma unidades a la existencia de un producto (tope: 100).
; =====================================================================
RecibirMercancia PROC
    pushad

    call LeerYBuscarCodigo        ; ESI = producto o 0
    cmp esi, 0
    je L_NoExiste
    mov ptrProducto, esi          ; Guarda la direccion (ESI se pierde al leer el entero)

    mov edx, OFFSET msgCantRec
    call LeerEntero               ; EAX = unidades a recibir
    jc L_ErrRec
    mov esi, ptrProducto          ; Recupera la direccion del producto

    cmp eax, 0
    je L_ErrRec                   ; Cantidad cero no es valida
    cmp eax, 100
    ja L_ExcedeMax                ; Una sola recepcion no puede pasar de 100

    add eax, [esi + 38]           ; EAX = unidades recibidas + existencia actual
    cmp eax, 100
    ja L_ExcedeMax                ; El total no puede pasar de 100

    mov [esi + 38], eax           ; Actualiza la existencia
    mov edx, OFFSET msgExitoRec
    call WriteString
    jmp L_FinRec

L_ExcedeMax:
    mov edx, OFFSET msgErrExceso
    call WriteString
    jmp L_FinRec

L_ErrRec:
    mov edx, OFFSET msgErrCant
    call WriteString
    jmp L_FinRec

L_NoExiste:
    mov edx, OFFSET msgNoEncontr
    call WriteString

L_FinRec:
    popad
    ret
RecibirMercancia ENDP

; =====================================================================
; 4. VENDER PRODUCTO (MAYOREO: 10% DE DESCUENTO DESDE 10 PIEZAS)
; Valida stock, calcula el importe (con descuento si aplica), revisa
; desbordamientos y solo entonces modifica ingresos y existencia.
; =====================================================================
VenderProducto PROC
    pushad

    call LeerYBuscarCodigo        ; ESI = producto o 0
    cmp esi, 0
    je L_NoEncVenta
    mov ptrProducto, esi

    mov edx, OFFSET msgCantVenta
    call LeerEntero               ; EAX = cantidad a vender
    jc L_ErrVenta
    mov esi, ptrProducto

    cmp eax, 0
    je L_ErrVenta
    mov ecx, eax                  ; ECX = cantidad
    cmp ecx, [esi + 38]
    ja L_SinStock                 ; Pide mas de lo que hay en existencia

    ; Importe = cantidad * precio
    mov eax, ecx
    mul DWORD PTR [esi + 34]      ; EDX:EAX = EAX * precio
    jc L_Desborde                 ; CF=1 si el resultado no cabe en 32 bits

    mov aplicoDesc, 0             ; Por defecto, sin descuento
    cmp ecx, 10
    jb L_SinDescuento             ; Menos de 10 piezas: sin mayoreo

    ; 10% de descuento: importe * 90 / 100 (se descarta la fraccion)
    mov ebx, 90
    mul ebx
    jc L_Desborde
    xor edx, edx                  ; Limpia EDX antes de dividir
    mov ebx, 100
    div ebx                       ; EAX = importe con descuento
    mov aplicoDesc, 1

L_SinDescuento:
    mov totalVenta, eax
    add eax, IngresosSesion       ; Suma al acumulado de ingresos
    jc L_Desborde                 ; nada se ha modificado todavia

    ; Venta aceptada: ahora si se actualizan datos
    mov IngresosSesion, eax       ; Guarda el nuevo acumulado
    mov eax, [esi + 38]
    sub eax, ecx                  ; Resta las piezas vendidas
    mov [esi + 38], eax

    mov edx, OFFSET msgVentaOk
    call WriteString
    cmp aplicoDesc, 0
    je L_SinMsgDesc
    mov edx, OFFSET msgDescuento  ; Avisa que se aplico el descuento
    call WriteString
L_SinMsgDesc:
    mov edx, OFFSET msgTotalVenta
    call WriteString
    mov eax, totalVenta
    call MostrarPrecioMXN         ; Imprime el total cobrado
    call Crlf
    jmp L_FinVenta

L_Desborde:
    mov edx, OFFSET msgDesborde
    call WriteString
    jmp L_FinVenta

L_SinStock:
    mov edx, OFFSET msgSinStock
    call WriteString
    jmp L_FinVenta

L_ErrVenta:
    mov edx, OFFSET msgErrCant
    call WriteString
    jmp L_FinVenta

L_NoEncVenta:
    mov edx, OFFSET msgNoEncontr
    call WriteString

L_FinVenta:
    popad
    ret
VenderProducto ENDP

; =====================================================================
; 5. MOSTRAR RESUMEN
; Calcula total de productos, unidades, valor del inventario e ingresos.
; =====================================================================
MostrarResumen PROC
    pushad
    mov edx, OFFSET msgResHead
    call WriteString

    xor ebx, ebx                  ; valor del inventario (centavos)
    xor edi, edi                  ; unidades disponibles
    mov ecx, TotalProductos
    cmp ecx, 0
    je L_MostrarRes               ; Sin productos: se muestran ceros
    mov esi, OFFSET Inventario

L_LoopRes:
    mov eax, [esi + 34]           ; precio
    mov edx, [esi + 38]           ; existencia
    add edi, edx                  ; Acumula unidades
    mul edx                       ; EAX = precio * existencia
    add ebx, eax                  ; Acumula valor del inventario
    add esi, TAM_PRODUCTO         ; Siguiente registro
    loop L_LoopRes

L_MostrarRes:
    mov edx, OFFSET msgResProd
    call WriteString
    mov eax, TotalProductos
    call ImprimirEntero
    call Crlf

    mov edx, OFFSET msgResUnid
    call WriteString
    mov eax, edi
    call ImprimirEntero
    call Crlf

    mov edx, OFFSET msgResValor
    call WriteString
    mov eax, ebx
    call MostrarPrecioMXN
    call Crlf

    mov edx, OFFSET msgResIngr
    call WriteString
    mov eax, IngresosSesion
    call MostrarPrecioMXN
    call Crlf

    popad
    ret
MostrarResumen ENDP

; =====================================================================
; 6. GUARDAR Y CARGAR ARCHIVO DE DISCO
; Formato: [TotalProductos: 4 bytes][Inventario: 420 bytes]
; =====================================================================
GuardarInventario PROC
    pushad
    mov edx, OFFSET NombreArchivo
    call CreateOutputFile         ; Crea (o sobrescribe) el archivo; EAX = handle
    mov fileHandle, eax
    cmp eax, INVALID_HANDLE_VALUE
    je L_ErrFile                  ; No se pudo crear el archivo

    ; Escribe primero el total de productos (4 bytes)
    mov eax, fileHandle
    mov edx, OFFSET TotalProductos
    mov ecx, 4
    call WriteToFile
    cmp eax, 4                    ; EAX = bytes escritos
    jne L_ErrEscr

    ; Luego escribe el arreglo completo del inventario (420 bytes)
    mov eax, fileHandle
    mov edx, OFFSET Inventario
    mov ecx, TAM_INVENTARIO
    call WriteToFile
    cmp eax, TAM_INVENTARIO
    jne L_ErrEscr

    mov eax, fileHandle
    call CloseFile                ; Cierra el archivo
    mov edx, OFFSET msgGuardado
    call WriteString
    jmp L_FinGuardar

L_ErrEscr:                        ; Error al escribir: cierra el archivo y avisa
    mov eax, fileHandle
    call CloseFile
L_ErrFile:
    mov edx, OFFSET errorGuardar
    call WriteString
L_FinGuardar:
    popad
    ret
GuardarInventario ENDP

; Lee inventario.dat a variables temporales, valida su contenido y solo
; si todo es correcto reemplaza el catalogo actual en memoria.
CargarInventario PROC
    pushad
    mov edx, OFFSET NombreArchivo
    call OpenInputFile            ; Abre el archivo para lectura; EAX = handle
    mov fileHandle, eax
    cmp eax, INVALID_HANDLE_VALUE
    je L_SinArchivo               ; El archivo no existe

    ; Leer total a temporal
    mov eax, fileHandle
    mov edx, OFFSET tmpTotal
    mov ecx, 4
    call ReadFromFile
    jc L_ArchivoMalo              ; CF=1: error de lectura
    cmp eax, 4                    ; EAX = bytes leidos
    jne L_ArchivoMalo

    ; Leer inventario a temporal
    mov eax, fileHandle
    mov edx, OFFSET tmpInv
    mov ecx, TAM_INVENTARIO
    call ReadFromFile
    jc L_ArchivoMalo
    cmp eax, TAM_INVENTARIO
    jne L_ArchivoMalo             ; Archivo incompleto

    mov eax, fileHandle
    call CloseFile

    ; Validar datos ANTES de reemplazar el catalogo
    cmp tmpTotal, MAX_PRODUCTOS
    ja L_Invalido                 ; Total fuera de rango
    mov ecx, tmpTotal
    cmp ecx, 0
    je L_Copiar                   ; Archivo con 0 productos: nada que validar
    mov esi, OFFSET tmpInv

L_ValReg:                         ; Valida cada registro del archivo
    call ValidarCodigoEn          ; ESI = inicio del registro
    jc L_Invalido
    cmp BYTE PTR [esi + 8], 0     ; nombre no vacio
    je L_Invalido
    cmp BYTE PTR [esi + 33], 0    ; nombre terminado en 0
    jne L_Invalido
    mov eax, [esi + 34]           ; precio: debe estar entre 1 y 999999 centavos
    cmp eax, 1
    jb L_Invalido
    cmp eax, 999999
    ja L_Invalido
    cmp DWORD PTR [esi + 38], 100 ; existencia: maximo 100
    ja L_Invalido
    add esi, TAM_PRODUCTO
    loop L_ValReg

L_Copiar:                         ; Todo valido: ahora si se reemplaza el catalogo
    mov eax, tmpTotal
    mov TotalProductos, eax
    mov esi, OFFSET tmpInv
    mov edi, OFFSET Inventario
    mov ecx, TAM_INVENTARIO
    rep movsb                     ; Copia los 420 bytes al inventario real
    mov edx, OFFSET msgCargado
    call WriteString
    jmp L_FinCarga

L_ArchivoMalo:                    ; Error de lectura: cierra el archivo y cae al mensaje de error
    mov eax, fileHandle
    call CloseFile
L_Invalido:
    mov edx, OFFSET errorArchivo
    call WriteString
    jmp L_FinCarga

L_SinArchivo:
    mov edx, OFFSET msgSinArchivo
    call WriteString

L_FinCarga:
    popad
    ret
CargarInventario ENDP

; =====================================================================
; AUXILIARES
; =====================================================================

; Pone en ceros los 30 bytes de bufferIn (evita basura de capturas previas)
LimpiarBuffer PROC
    push edi
    push ecx
    push eax
    mov edi, OFFSET bufferIn
    mov ecx, 30
    xor al, al                    ; AL = 0
    rep stosb                     ; Rellena 30 bytes con 0
    pop eax
    pop ecx
    pop edi
    ret
LimpiarBuffer ENDP

; Devuelve en ESI la direccion del primer registro libre:
; Inventario + (TotalProductos * TAM_PRODUCTO)
ObtenerPunteroLibre PROC
    push eax
    push ebx
    push edx
    mov eax, TotalProductos
    mov ebx, TAM_PRODUCTO
    mul ebx                       ; EAX = TotalProductos * 42
    mov esi, OFFSET Inventario
    add esi, eax
    pop edx
    pop ebx
    pop eax
    ret
ObtenerPunteroLibre ENDP

; Valida que la cadena apuntada por ESI tenga 3 letras mayusculas (A-Z),
; un guion y 3 digitos (0-9). CF=1 si es invalido. ESI se conserva.
ValidarCodigoEn PROC
    push esi
    push ecx
    push eax
    mov ecx, 3                    ; Revisa 3 letras
L_Letras:
    mov al, [esi]
    cmp al, 'A'
    jb L_CodMal                   ; Menor que 'A': no es mayuscula
    cmp al, 'Z'
    ja L_CodMal                   ; Mayor que 'Z': no es mayuscula
    inc esi
    loop L_Letras

    cmp BYTE PTR [esi], '-'       ; Cuarto caracter debe ser guion
    jne L_CodMal
    inc esi

    mov ecx, 3                    ; Revisa 3 digitos
L_Digitos:
    mov al, [esi]
    cmp al, '0'
    jb L_CodMal
    cmp al, '9'
    ja L_CodMal
    inc esi
    loop L_Digitos

    cmp BYTE PTR [esi], 0         ; Despues del septimo caracter debe terminar la cadena
    jne L_CodMal
    clc                           ; CF=0: codigo valido
    jmp L_FinCod
L_CodMal:
    stc                           ; CF=1: codigo invalido
L_FinCod:
    pop eax
    pop ecx
    pop esi
    ret
ValidarCodigoEn ENDP

; Pide un codigo y lo busca. Devuelve ESI = producto o 0
LeerYBuscarCodigo PROC
    call LimpiarBuffer
    mov edx, OFFSET msgCodProd
    call WriteString
    mov edx, OFFSET bufferIn
    mov ecx, 29
    call ReadString
    cmp eax, 7
    jne L_CodInv                  ; Longitud incorrecta
    mov esi, OFFSET bufferIn
    call ValidarCodigoEn
    jc L_CodInv                   ; Formato incorrecto
    call BuscarProductoPorCodigo  ; ESI = registro o 0
    ret
L_CodInv:
    xor esi, esi                  ; ESI = 0 significa "no encontrado"
    ret
LeerYBuscarCodigo ENDP

; Busca el codigo de bufferIn. Retorna ESI = registro o 0
BuscarProductoPorCodigo PROC
    push ecx
    mov ecx, TotalProductos
    cmp ecx, 0
    je L_NoFnd                    ; Catalogo vacio: no hay nada que buscar
    mov esi, OFFSET Inventario

L_CheckNext:
    push esi                      ; Guarda ESI y ECX porque cmpsb los modifica
    push ecx
    mov edi, OFFSET bufferIn
    mov ecx, 7
    repe cmpsb                    ; Compara 7 bytes del registro contra bufferIn
    pop ecx
    pop esi
    je L_Encontrado               ; ZF=1: los 7 caracteres coinciden

    add esi, TAM_PRODUCTO         ; Siguiente registro
    loop L_CheckNext

L_NoFnd:
    mov esi, 0                    ; No se encontro
L_Encontrado:
    pop ecx
    ret
BuscarProductoPorCodigo ENDP

; EDX = mensaje a mostrar. Lee una linea con ReadString y la convierte a
; entero sin signo de hasta 4 digitos. Retorna EAX, CF=1 si es invalida.
LeerEntero PROC
    call WriteString              ; Imprime el mensaje que viene en EDX
    call LimpiarBuffer
    mov edx, OFFSET bufferIn
    mov ecx, 29
    call ReadString
    call StringAEntero            ; Convierte el texto a numero
    ret
LeerEntero ENDP

; Convierte bufferIn (solo digitos, 1 a 4) a entero en EAX. CF=1 si error.
StringAEntero PROC
    push ebx
    push ecx
    push esi
    xor eax, eax                  ; EAX = acumulador del numero
    xor ecx, ecx                  ; ECX = cantidad de digitos leidos
    mov esi, OFFSET bufferIn
L_EntLp:
    movzx ebx, BYTE PTR [esi]     ; Toma un caracter
    cmp bl, 0
    je L_EntFin                   ; Fin de la cadena
    cmp bl, '0'
    jb L_EntErr                   ; No es digito
    cmp bl, '9'
    ja L_EntErr                   ; No es digito
    sub bl, '0'                   ; ASCII -> valor numerico
    imul eax, eax, 10             ; eax = eax * 10
    add eax, ebx                  ; eax = eax + digito
    inc ecx
    cmp ecx, 4
    ja L_EntErr                   ; Mas de 4 digitos: invalido
    inc esi
    jmp L_EntLp
L_EntFin:
    cmp ecx, 0
    je L_EntErr                   ; Cadena vacia: invalido
    clc                           ; CF=0: conversion correcta
    jmp L_EntSal
L_EntErr:
    stc                           ; CF=1: error
L_EntSal:
    pop esi
    pop ecx
    pop ebx
    ret
StringAEntero ENDP

; Convierte bufferIn ("18", "18.5", "18.50") a centavos en EAX.
; Rango 1 a 999999. CF=1 si el formato es invalido (rechaza 3er decimal).
StringACentavos PROC
    push ebx
    push ecx
    push esi
    xor eax, eax                  ; EAX = acumulador (en centavos al final)
    xor ecx, ecx                  ; digitos enteros
    mov esi, OFFSET bufferIn

L_EnteroLp:                       ; Lee la parte entera (pesos)
    movzx ebx, BYTE PTR [esi]
    cmp bl, 0
    je L_SinPunto                 ; Termino sin punto decimal
    cmp bl, '.'
    je L_Punto                    ; Encontro el punto decimal
    cmp bl, '0'
    jb L_ErrConv
    cmp bl, '9'
    ja L_ErrConv
    sub bl, '0'
    imul eax, eax, 10
    add eax, ebx
    inc ecx
    cmp ecx, 4
    ja L_ErrConv                  ; Maximo 4 digitos enteros (9999)
    inc esi
    jmp L_EnteroLp

L_SinPunto:                       ; Ejemplo: "18" -> 1800 centavos
    cmp ecx, 0
    je L_ErrConv                  ; Cadena vacia
    imul eax, eax, 100
    jmp L_Rango

L_Punto:                          ; Hay punto decimal: procesa 1 o 2 decimales
    cmp ecx, 0
    je L_ErrConv                  ; No se permite ".50" sin parte entera
    inc esi
    movzx ebx, BYTE PTR [esi]     ; primer decimal (obligatorio)
    cmp bl, '0'
    jb L_ErrConv
    cmp bl, '9'
    ja L_ErrConv
    sub bl, '0'
    imul eax, eax, 10
    add eax, ebx
    inc esi
    movzx ebx, BYTE PTR [esi]     ; segundo decimal (opcional)
    cmp bl, 0
    je L_UnDecimal                ; Solo habia un decimal
    cmp bl, '0'
    jb L_ErrConv
    cmp bl, '9'
    ja L_ErrConv
    sub bl, '0'
    imul eax, eax, 10
    add eax, ebx
    inc esi
    cmp BYTE PTR [esi], 0         ; un tercer caracter se rechaza
    jne L_ErrConv
    jmp L_Rango

L_UnDecimal:
    imul eax, eax, 10             ; "18.5" -> 1850

L_Rango:                          ; Valida que el precio este entre $0.01 y $9999.99
    cmp eax, 1
    jb L_ErrConv
    cmp eax, 999999
    ja L_ErrConv
    clc                           ; CF=0: valido
    jmp L_FinConv

L_ErrConv:
    stc                           ; CF=1: invalido
L_FinConv:
    pop esi
    pop ecx
    pop ebx
    ret
StringACentavos ENDP

; Imprime el entero sin signo de EAX en decimal usando WriteString.
; Cociente/residuo: se divide entre 10, cada residuo se convierte a ASCII
; (+ '0'), se apila y luego se desapila para escribirlos en orden correcto.
ImprimirEntero PROC
    pushad
    mov ebx, 10                   ; Divisor
    xor ecx, ecx                  ; ECX = cuantos digitos se han generado
L_DivLp:
    xor edx, edx                  ; Limpia EDX antes de dividir (EDX:EAX / EBX)
    div ebx                       ; EAX = cociente, EDX = residuo (ultimo digito)
    add dl, '0'                   ; Digito -> caracter ASCII
    push edx                      ; Se apila (los digitos salen al reves)
    inc ecx
    cmp eax, 0
    jne L_DivLp                   ; Repite hasta que el cociente sea 0

    mov esi, OFFSET bufNum
L_PopLp:
    pop edx                       ; Al desapilar quedan en el orden correcto
    mov [esi], dl                 ; Guarda el caracter en el buffer
    inc esi
    loop L_PopLp
    mov BYTE PTR [esi], 0         ; Terminador de cadena

    mov edx, OFFSET bufNum
    call WriteString              ; Imprime el numero
    popad
    ret
ImprimirEntero ENDP

; EAX = centavos. Imprime "$18.50 MXN"
MostrarPrecioMXN PROC
    pushad
    xor edx, edx
    mov ebx, 100
    div ebx                       ; EAX = pesos, EDX = centavos
    push edx                      ; Guarda centavos
    push eax                      ; Guarda pesos
    mov edx, OFFSET strDolar
    call WriteString              ; Imprime "$"
    pop eax                       ; Recupera pesos
    call ImprimirEntero
    mov edx, OFFSET strPunto
    call WriteString              ; Imprime "."
    pop eax                       ; centavos
    cmp eax, 10
    jae L_DosDig                  ; Si tiene 2 digitos, no hace falta rellenar
    push eax
    mov edx, OFFSET strCero       ; 5 -> "05"
    call WriteString
    pop eax
L_DosDig:
    call ImprimirEntero           ; Imprime los centavos
    mov edx, OFFSET etiquetaMXN
    call WriteString              ; Imprime " MXN"
    popad
    ret
MostrarPrecioMXN ENDP

END mainS