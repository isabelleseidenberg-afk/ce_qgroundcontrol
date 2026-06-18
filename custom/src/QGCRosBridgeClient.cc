#include "QGCRosBridgeClient.h"

#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QDebug>
#include <QtNetwork/QNetworkDatagram>
#include <QtNetwork/QUdpSocket>

QGCRosBridgeClient::QGCRosBridgeClient(QObject *parent)
    : QObject(parent)
    , _socket(new QUdpSocket(this))
    , _statusSocket(new QUdpSocket(this))
{
    connect(_statusSocket, &QUdpSocket::readyRead, this, &QGCRosBridgeClient::_readPendingStatusDatagrams);
    _bindStatusSocket();
}

QString QGCRosBridgeClient::host() const
{
    return _host;
}

void QGCRosBridgeClient::setHost(const QString &host)
{
    if (_host == host) {
        return;
    }

    _host = host;
    emit hostChanged();
}

int QGCRosBridgeClient::port() const
{
    return static_cast<int>(_port);
}

void QGCRosBridgeClient::setPort(int port)
{
    if (port < 1 || port > 65535) {
        qWarning() << "QGCRosBridgeClient invalid port" << port;
        return;
    }

    const quint16 newPort = static_cast<quint16>(port);
    if (_port == newPort) {
        return;
    }

    _port = newPort;
    emit portChanged();
}

int QGCRosBridgeClient::statusPort() const
{
    return static_cast<int>(_statusPort);
}

void QGCRosBridgeClient::setStatusPort(int port)
{
    if (port < 1 || port > 65535) {
        qWarning() << "QGCRosBridgeClient invalid status port" << port;
        return;
    }

    const quint16 newPort = static_cast<quint16>(port);
    if (_statusPort == newPort) {
        return;
    }

    _statusPort = newPort;
    _bindStatusSocket();
    emit statusPortChanged();
}

void QGCRosBridgeClient::_bindStatusSocket()
{
    _statusSocket->close();
    if (!_statusSocket->bind(QHostAddress::LocalHost, _statusPort, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        qWarning() << "QGCRosBridgeClient status bind failed" << _statusPort << _statusSocket->errorString();
    }
}

void QGCRosBridgeClient::_readPendingStatusDatagrams()
{
    while (_statusSocket->hasPendingDatagrams()) {
        const QByteArray datagram = _statusSocket->receiveDatagram().data();
        emit messageReceived(QString::fromUtf8(datagram));
    }
}

bool QGCRosBridgeClient::sendJsonMessage(const QVariantMap &message)
{
    const QHostAddress address(_host);
    if (address.isNull()) {
        emit sendFailed(QStringLiteral("Invalid ROS bridge host: %1").arg(_host));
        return false;
    }

    const QJsonObject object = QJsonObject::fromVariantMap(message);
    const QByteArray bytes = QJsonDocument(object).toJson(QJsonDocument::Compact);
    const qint64 sent = _socket->writeDatagram(bytes, address, _port);
    if (sent != bytes.size()) {
        qWarning() << "QGCRosBridgeClient UDP send failed" << _socket->errorString();
        emit sendFailed(_socket->errorString());
        return false;
    }

    qInfo() << "QGCRosBridgeClient UDP sent" << _host << _port << bytes;
    emit messageSent(QString::fromUtf8(bytes));
    return true;
}
